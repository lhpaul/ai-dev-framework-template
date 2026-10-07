#!/usr/bin/env python3
"""Read-only, invocation-scoped GitHub Projects portfolio coordination."""
import argparse
from datetime import date, datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid

sys.dont_write_bytecode = True
SCRIPT_DIR = Path(__file__).resolve().parent

def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

reader = load_module('workflow_project_reader', SCRIPT_DIR / 'workflow-project-reader.py')
resolver = load_module('workflow_config_resolver', SCRIPT_DIR / 'workflow-config-resolver.py')
routing = load_module('work_item_repository_routing', SCRIPT_DIR / 'work-item-repository-routing.py')
ReadError = reader.ReadError
FULL = 'Full scan'
PARTIAL = 'Partial scan (budget-limited)'
DEFERRED = 'Scan deferred (budget too low)'
TERMINAL = {'Merged', 'Released', 'Cancelled'}
P, Q = 2, 21
# Same routine-tier ordering as workflow-batch-overlap.sh's PRIORITY_RANK.
PRIORITY_RANK = {'urgent': 0, 'high': 1, 'normal': 2, 'medium': 2, 'low': 3}


class EvidenceIncomplete(ReadError):
    """A successfully read item cannot advance until bounded reconciliation."""


def dependency_references(text, slug_ids=None):
    # Canonical spec Depends on and plan Dependencies fields, including
    # Markdown formatting and the plan template's explicit None vocabulary.
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    lines = text.splitlines()
    references = set()
    for index, line in enumerate(lines):
        clean = line.strip().strip('|').replace('**', '')
        match = re.match(r'(?i)^(?:[-*]\s*|#{1,6}\s*)?(dependson|depends on|blocked by|dependency|dependencies)\b\s*:?(.*)$', clean)
        if not match:
            continue
        value = match[2].strip().strip('|').strip()
        if not value:
            section = []
            for following in lines[index + 1:]:
                if re.match(r'^\s*#{1,6}\s', following):
                    break
                if following.strip():
                    section.append(following.strip())
            value = ' '.join(section)
        if re.fullmatch(r'(?i)none\.?', value) or re.match(r'(?i)^none\.\s+', value):
            continue
        # Each comma-delimited member is evidence in its own right. A #ref
        # must not mask a supported slug or an unresolved neighbouring member.
        for member in value.split(','):
            found = re.findall(r'#([1-9][0-9]*)\b', member)
            if found:
                references.update(int(n) for n in found)
                continue
            slug = re.sub(r'^(?:feature|fix|refactor|hotfix)/', '', member.strip().strip('[]`'))
            if slug not in (slug_ids or {}):
                raise EvidenceIncomplete('Unresolved dependency declaration')
            references.add(slug_ids[slug])
    return references



def run(args, root):
    result = subprocess.run(args, cwd=root, text=True, capture_output=True)
    if result.returncode:
        raise ReadError(result.stderr.strip() or 'Local evidence read failed')
    return result.stdout


def repository(root):
    remote = run(['git', 'remote', 'get-url', 'origin'], root).strip()
    match = re.fullmatch(r'(?:https://(?:[^/@]+@)?github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9-]+/[A-Za-z0-9_.-]+?)(?:\.git)?', remote)
    if not match:
        raise ReadError('Cannot resolve GitHub repository from origin')
    return match[1]


def configuration(root):
    path = Path(os.environ.get('AI_DEV_WORKFLOW_CONFIG_FILE', str(root / '.ai-dev-workflow.yaml')))
    if not path.is_file():
        path = root / '.ai-dev-workflow.yaml'
    return resolver.parse_yaml_subset(path, preserve_empty_values=True)


def tracker_scope(config, repo):
    project = os.environ.get('GITHUB_PROJECT_NUMBER') or (config.get('issue_tracker') or {}).get('project_number', '')
    owner = os.environ.get('GITHUB_PROJECT_OWNER') or repo.split('/')[0]
    if not re.fullmatch(r'[1-9][0-9]*', str(project)):
        raise ReadError('Missing configured project number')
    return owner, str(project)


def reserve_from_config(config, warnings):
    section = config.get('portfolio_scan', {})
    if isinstance(section, dict) and 'graphql_reserve' not in section:
        return 1000
    value = section.get('graphql_reserve') if isinstance(section, dict) else None
    if type(value) is int and 0 <= value <= 5000:
        return value
    if isinstance(value, str) and re.fullmatch(r'[0-9]+', value) and int(value) <= 5000:
        return int(value)
    warnings.append('Invalid portfolio_scan.graphql_reserve; using 1000')
    return 1000


def budget(client):
    try:
        value = client.rest('rate_limit')['resources']['graphql']
        if not isinstance(value, dict) or any(type(value.get(k)) is not int or value[k] < 0 for k in ('remaining', 'reset')):
            return None
        return value
    except (ReadError, KeyError, TypeError):
        return None


def rate_limited(error):
    # Same rate-limit vocabulary as run-work-router.sh/#1503. Unknown errors fail.
    if any(isinstance(item, dict) and item.get('type') == 'RATE_LIMITED' for item in getattr(error, 'errors', [])):
        return True
    text = str(error).lower()
    return any(value in text for value in ('api rate limit', 'rate limit exceeded', 'secondary rate limit'))


def issue_number(branch):
    match = re.match(r'^(?:spec|implementation-plan|feature|fix|refactor|hotfix)/(?:[A-Z][A-Z0-9]*-)?([1-9][0-9]*)(?:-|$)', branch)
    return int(match[1]) if match else None


def current_local_evidence(root):
    folders = {}
    base = root / 'docs/specs/developments'
    if base.is_dir():
        for folder in sorted(base.iterdir()):
            if not folder.is_dir():
                continue
            # Match workflow-lib's extract_github_issue_number: document first,
            # then numeric slug, including folders with no timestamp prefix.
            number = None
            for document in sorted(folder.glob('*.md')):
                match = re.search(r'^\*\*Issue\*\*:\s*\[?#([0-9]+)', document.read_text(), re.MULTILINE)
                if match:
                    number = int(match[1])
                    break
            if number is None:
                slug = re.sub(r'^\d{14}_', '', folder.name)
                match = re.match(r'^([1-9][0-9]*)-', slug)
                if not match:
                    continue
                number = int(match[1])
            if number in folders:
                raise ReadError(f'Duplicate development folders for #{number}')
            folders[number] = {'development_path': str(folder.relative_to(root)),
                               'spec': any(folder.glob('1_*_specs.md')) or any(folder.glob('1_*_specs.doc.md')),
                               'plan': any(folder.glob('2_*_implementation-plan.md')) or any(folder.glob('2_*_implementation-plan.doc.md'))}
    branches = {}
    local_refs = run(['git', 'for-each-ref', '--format=%(refname:short)', 'refs/heads'], root)
    for branch in local_refs.splitlines():
        number = issue_number(branch)
        if number:
            branches.setdefault(number, []).append(branch)
    refs = run(['git', 'ls-remote', '--heads', 'origin'], root)
    for line in refs.splitlines():
        parts = line.split('\t')
        if len(parts) != 2:
            raise ReadError('Malformed remote branch evidence')
        branch = parts[1].removeprefix('refs/heads/')
        number = issue_number(branch)
        if number:
            if branch not in branches.setdefault(number, []):
                branches[number].append(branch)
    return folders, branches


def project_id(client, owner, number):
    for kind in ('user', 'organization'):
        query = 'query($owner:String!,$number:Int!) { %s(login:$owner) { projectV2(number:$number) { id } } rateLimit { cost } }' % kind
        try:
            data = client.graphql(query, owner=owner, number=number)
        except ReadError as exc:
            if kind == 'user' and exc.errors and all(isinstance(error, dict) and error.get('type') == 'NOT_FOUND' and error.get('path', [])[:1] == ['user'] for error in exc.errors):
                continue
            raise
        value = (data.get(kind) or {}).get('projectV2')
        if isinstance(value, dict) and isinstance(value.get('id'), str) and value['id']:
            return value['id']
    raise ReadError('Configured project unavailable')


def validate_pr_evidence(pr, expected_issue):
    if (not isinstance(pr, dict) or type(pr.get('number')) is not int or pr['number'] <= 0 or
            any(not isinstance(pr.get(key), str) or not pr[key] for key in ('branch', 'sha')) or
            issue_number(pr['branch']) != expected_issue or type(pr.get('draft')) is not bool or
            not isinstance(pr.get('labels'), list) or any(not isinstance(label, str) for label in pr['labels']) or
            not isinstance(pr.get('comments'), list) or any(not isinstance(comment, dict) or not isinstance(comment.get('body'), str) for comment in pr['comments'])):
        raise ReadError('Incomplete PR identity/comment evidence')
    status, checks = pr.get('status'), pr.get('checks')
    if (not isinstance(status, dict) or not isinstance(status.get('state'), str) or not status['state'] or
            not isinstance(status.get('statuses'), list) or
            any(not isinstance(entry, dict) or not isinstance(entry.get('state'), str) or not entry['state'] for entry in status['statuses']) or
            ('sha' in status and status['sha'] != pr['sha']) or
            not isinstance(checks, dict) or not isinstance(checks.get('check_runs'), list)):
        raise ReadError('Incomplete PR status/check evidence')
    for check in checks['check_runs']:
        if (not isinstance(check, dict) or not isinstance(check.get('status'), str) or not check['status'] or
                'conclusion' not in check or (check['conclusion'] is not None and not isinstance(check['conclusion'], str)) or
                ('head_sha' in check and check['head_sha'] != pr['sha'])):
            raise ReadError('Incomplete PR check evidence')


def complete_pr(client, repo, pr, expected_issue):
    number = pr.get('number')
    if type(number) is not int:
        raise ReadError('Missing open PR identity')
    detail = client.rest(f'repos/{repo}/pulls/{number}')
    head = detail.get('head') if isinstance(detail, dict) else None
    if not isinstance(head, dict) or detail.get('number') != number or not head.get('sha') or head.get('ref') != (pr.get('head') or {}).get('ref') or not isinstance(detail.get('draft'), bool) or not isinstance(detail.get('labels'), list) or any(not isinstance(label, dict) or not isinstance(label.get('name'), str) for label in detail['labels']):
        raise ReadError('Incomplete PR evidence')
    comments = client.rest(f'repos/{repo}/issues/{number}/comments?per_page=100', paginate=True)
    status = client.rest(f'repos/{repo}/commits/{head["sha"]}/status')
    check_pages = client.call(['api', '--paginate', '--slurp', f'repos/{repo}/commits/{head["sha"]}/check-runs?per_page=100'])
    if not isinstance(check_pages, list) or any(not isinstance(page, dict) or not isinstance(page.get('check_runs'), list) for page in check_pages):
        raise ReadError('Incomplete PR check pagination')
    checks = {'check_runs': [check for page in check_pages for check in page['check_runs']]}
    if not isinstance(status, dict) or not isinstance(checks, dict) or not isinstance(checks.get('check_runs'), list):
        raise ReadError('Incomplete PR status evidence')
    result = {'number': number, 'branch': head['ref'], 'sha': head['sha'], 'draft': detail['draft'],
            'labels': [label['name'] for label in detail['labels'] if isinstance(label, dict) and isinstance(label.get('name'), str)],
            'comments': comments, 'status': status, 'checks': checks}
    validate_pr_evidence(result, expected_issue)
    return result


def complete_record(client, repo, issue, card, folders, branches, prs, root):
    number = issue['number']
    if any(not isinstance(card.get(key), str) or not card[key] for key in ('item_id', 'project_id', 'status', 'type')):
        raise EvidenceIncomplete('Incomplete Status/Type/project membership')
    try:
        if not isinstance(issue.get('created_at'), str) or not issue['created_at']:
            raise ValueError('Missing creation timestamp')
        if datetime.fromisoformat(issue['created_at'].replace('Z', '+00:00')).tzinfo is None:
            raise ValueError('Missing creation timestamp timezone')
        if card.get('due_date'):
            date.fromisoformat(card['due_date'])
    except (ValueError, TypeError):
        raise EvidenceIncomplete('Incomplete Due date/creation evidence')
    folder = folders.get(number, {})
    current_prs = [complete_pr(client, repo, pr, number) for pr in prs if issue_number((pr.get('head') or {}).get('ref', '')) == number]
    body = issue.get('body') or ''
    if not isinstance(body, str):
        raise EvidenceIncomplete('Incomplete dependency evidence')
    if card.get('depends_on'):
        body += '\nDependsOn: ' + card['depends_on']
    slug_ids = {re.sub(r'^\d{14}_', '', Path(value['development_path']).name): key for key, value in folders.items()}
    dependencies = dependency_references(body, slug_ids)
    if folder.get('development_path'):
        artifact_root = root / folder['development_path']
        try:
            for kind, patterns in (('spec', ('1_*_specs.md', '1_*_specs.doc.md')), ('plan', ('2_*_implementation-plan.md', '2_*_implementation-plan.doc.md'))):
                documents = [document for pattern in patterns for document in artifact_root.glob(pattern)]
                if folder.get(kind) and not documents:
                    raise EvidenceIncomplete('Artifact dependency evidence disappeared')
                for document in documents:
                    dependencies.update(dependency_references(document.read_text(), slug_ids))
        except OSError as exc:
            raise EvidenceIncomplete('Artifact dependency evidence unreadable') from exc
    dependencies = sorted(dependencies)
    dependency_states = {}
    record = {'number': number, 'title': issue['title'], 'body': body, 'created_at': issue['created_at'], **card, **folder,
              'branches': branches.get(number, []), 'prs': current_prs, 'dependencies': dependencies,
              'inFlight': bool(folder or branches.get(number) or current_prs), 'dependencyStates': dependency_states}
    # Bounded REST lookup for the expected active implementation branch only.
    if folder.get('plan') and not current_prs and not any(branch.startswith(('feature/', 'fix/', 'refactor/', 'hotfix/')) for branch in record['branches']):
        slug = re.sub(r'^\d{14}_', '', Path(folder['development_path']).name)
        prefix = 'feature' if folder.get('spec') else 'refactor'
        record['implementationMerged'] = False
        # Preserve the canonical feature/refactor head, and reconcile exact
        # fix/hotfix heads too for plan-backed bug work. No portfolio sweep.
        for branch_prefix in (prefix, 'fix', 'hotfix'):
            expected_head = f'{branch_prefix}/{slug}'
            closed = client.rest(f'repos/{repo}/pulls?state=closed&head={repo.split("/")[0]}:{expected_head}&per_page=100', paginate=True)
            if any(not isinstance(pr, dict) or not isinstance(pr.get('head'), dict) or pr['head'].get('ref') != expected_head or 'merged_at' not in pr or (pr['merged_at'] is not None and not isinstance(pr['merged_at'], str)) for pr in closed):
                raise EvidenceIncomplete('Incomplete merged implementation evidence')
            if any(isinstance(pr, dict) and isinstance(pr.get('head'), dict) and pr['head'].get('ref') == expected_head and isinstance(pr.get('merged_at'), str) and pr['merged_at'] for pr in closed):
                record['implementationMerged'] = True
                break
    record['fullyRead'] = True
    return record


def classify(record, snapshot):
    if not record.get('fullyRead'):
        return 'HELD', 'hold-unreadable', 'Item was not fully read'
    status = record['status']
    if status in TERMINAL:
        return 'INFORMATIONAL', 'skip', 'Terminal tracker status'
    if status == 'Backlog' and snapshot['framework'] and record['type'] == 'Workflow' and not (record.get('spec') or record.get('plan') or record['branches'] or record['prs']):
        return 'HELD', 'hold-misclassified-type', 'Framework Backlog Type Workflow requires reclassification'
    if any(record['dependencyStates'].get(str(n)) not in ('Merged', 'Released') for n in record['dependencies']):
        return 'HELD', 'hold-dependency', 'Dependency readiness requires bounded reconciliation'
    if record['prs']:
        pr = record['prs'][0]
        if 'ready-for-human-review' in pr['labels']:
            return 'INFORMATIONAL', 'wait-human-review', 'Current PR awaits human/delegated gate'
        return 'ACTIONABLE RESUME', 'resume-fix-loop' if 'needs-fixes' in pr['labels'] else 'resolve-pr-readiness', 'Current PR can resume bounded review'
    expected_prefixes = ('spec/',) if status in ('Writing Spec', 'Spec in Review') else ('implementation-plan/',) if status in ('Writing Plan', 'Plan in Review') else ('feature/', 'fix/', 'refactor/', 'hotfix/') if status in ('In Development', 'Development in Review', 'Plan Ready') else ()
    if status == 'Backlog':
        if record.get('plan'):
            expected_prefixes = ('feature/', 'fix/', 'refactor/', 'hotfix/')
        elif not record.get('spec'):
            expected_prefixes = ('spec/', 'implementation-plan/', 'feature/', 'fix/', 'refactor/', 'hotfix/')
    active_branches = [branch for branch in record['branches'] if branch.startswith(expected_prefixes)]
    if active_branches:
        prefix = active_branches[0].split('/')[0]
        action = 'run-spec-review-and-open-pr' if prefix == 'spec' else 'run-plan-review-and-open-pr' if prefix == 'implementation-plan' else 'run-code-review-and-open-pr'
        return 'ACTIONABLE RESUME', action, 'Current workflow branch exists'
    if status == 'Spec Ready' and record.get('spec'):
        return 'PROPOSED BATCH', 'write-plan', 'Approved spec ready for planning'
    if status == 'Plan Ready' and record.get('plan'):
        if record.get('implementationMerged'):
            return 'HELD', 'reconcile-tracker', 'Merged implementation evidence conflicts with Plan Ready'
        return 'PROPOSED BATCH', 'implement', 'Approved plan ready for implementation'
    if status == 'Backlog':
        if record.get('plan'):
            if record.get('implementationMerged'):
                return 'HELD', 'reconcile-tracker', 'Merged implementation evidence conflicts with Backlog'
            return 'PROPOSED BATCH', 'implement', 'Stale Backlog reconciled from existing plan artifacts'
        if record.get('spec'):
            return 'PROPOSED BATCH', 'write-plan', 'Stale Backlog reconciled from existing spec artifacts'
        if snapshot['coverage'] == PARTIAL:
            return 'HELD', 'skip-backlog-discovery', 'Partial scan skips new Backlog starts'
        return 'PROPOSED BATCH', ('implement' if record['type'] == 'Bug' else 'write-plan' if record['type'] == 'Refactor' else 'write-spec'), 'Current Backlog work'
    return 'HELD', 'reconcile-stage', 'Tracker/artifact evidence needs bounded reconciliation'


def snapshot_read(path, root):
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError) as exc:
        raise ReadError('Malformed scan snapshot') from exc
    invocation = os.environ.get('WORKFLOW_SCAN_INVOCATION_ID')
    config = configuration(root)
    repo = repository(root)
    owner, project = tracker_scope(config, repo)
    if not invocation or not isinstance(data, dict) or data.get('invocation') != invocation or data.get('repo', '').lower() != repo.lower() or data.get('projectNumber') != project or data.get('projectOwner') != owner or data.get('coverage') not in (FULL, PARTIAL, DEFERRED) or not isinstance(data.get('fullyRead'), list):
        raise ReadError('Scan snapshot repository/project/invocation scope mismatch')
    open_ids = data.get('openIdentities')
    if not isinstance(open_ids, list) or any(type(n) is not int for n in open_ids):
        raise ReadError('Invalid open identity evidence')
    seen = set()
    for record in data['fullyRead']:
        if not isinstance(record, dict) or record.get('fullyRead') is not True or type(record.get('number')) is not int or record['number'] not in open_ids or record['number'] in seen or not record.get('status') or not record.get('type') or any(key not in record for key in ('prs', 'branches', 'dependencies', 'dependencyStates', 'inFlight', 'due_date', 'priority', 'created_at')):
            raise ReadError('Incomplete or duplicate scan record')
        if (any(not isinstance(record.get(key), str) or not record[key] for key in ('item_id', 'project_id', 'status', 'type')) or
                not isinstance(data.get('projectId'), str) or not data['projectId'] or record['project_id'] != data['projectId'] or
                'membership' in record):
            raise ReadError('Incomplete or mismatched scan project membership')
        if any(not isinstance(record.get(key), str) for key in ('title', 'body', 'due_date', 'priority', 'created_at')) or not record['created_at']:
            raise ReadError('Malformed scan ordering evidence')
        if datetime.fromisoformat(record['created_at'].replace('Z', '+00:00')).tzinfo is None:
            raise ReadError('Missing creation timestamp timezone')
        if record['due_date']:
            date.fromisoformat(record['due_date'])
        if not isinstance(record['prs'], list) or not isinstance(record['branches'], list) or any(not isinstance(branch, str) for branch in record['branches']) or not isinstance(record['dependencies'], list) or any(type(n) is not int for n in record['dependencies']) or not isinstance(record['dependencyStates'], dict) or type(record['inFlight']) is not bool:
            raise ReadError('Malformed scan evidence types')
        if (any(issue_number(branch) != record['number'] for branch in record['branches']) or
                any(not isinstance(record['dependencyStates'].get(str(n)), str) or not record['dependencyStates'][str(n)] for n in record['dependencies']) or
                any(key in record and type(record[key]) is not bool for key in ('spec', 'plan', 'implementationMerged'))):
            raise ReadError('Incomplete scan branch/dependency evidence')
        for pr in record['prs']:
            validate_pr_evidence(pr, record['number'])
        if record.get('plan') and not record['prs'] and not any(branch.startswith(('feature/', 'fix/', 'refactor/', 'hotfix/')) for branch in record['branches']) and 'implementationMerged' not in record:
            raise ReadError('Incomplete merged implementation evidence')
        seen.add(record['number'])
    return data


def branch_identity(record):
    implementation = ('feature/', 'fix/', 'refactor/', 'hotfix/')
    branches = [pr['branch'] for pr in record['prs'] if isinstance(pr.get('branch'), str)] + record['branches']
    return next((branch for branch in branches if branch.startswith(implementation)), str(record['number']))


def portfolio_sort_key(record, today):
    due = date.fromisoformat(record['due_date']) if record['due_date'] else None
    near_due = due is not None and due <= today + timedelta(days=14)
    created = datetime.fromisoformat(record['created_at'].replace('Z', '+00:00'))
    if created.tzinfo is None:
        raise ReadError('Missing creation timestamp timezone')
    return (0 if near_due else 1, due if near_due else date.max,
            PRIORITY_RANK.get(record['priority'].lower(), 2), created,
            branch_identity(record), record['number'])


def implementation_candidate(row, record):
    if row['action'] in ('implement', 'resolve-development-pr', 'run-code-review-and-open-pr'):
        return True
    return row['action'] in ('resume-fix-loop', 'resolve-pr-readiness') and branch_identity(record).startswith(('feature/', 'fix/', 'refactor/', 'hotfix/'))


def batch_safety(output, records):
    eligible = [row for row in output if row['category'] in ('PROPOSED BATCH', 'ACTIONABLE RESUME')]
    hazards = [row for row in output if row['toolFix'] in ('yes', 'unknown') and
               (row in eligible or row['action'] == 'wait-human-review' or records[row['number']]['status'] in ('Spec in Review', 'Plan in Review', 'Development in Review'))]
    pending = [row for row in hazards if row not in eligible]
    if hazards:
        first = (pending or hazards)[0]
        for row in eligible:
            if pending or row is not first:
                row['category'], row['dispatch'] = 'HELD', 'held'
                row['reason'] = f'Pending tool-fix merge for #{first["number"]} (TOOL_FIX={first["toolFix"]}); serialize tool fixes before consumers'
    overlap_items = []
    for row in output:
        record = records[row['number']]
        if row['category'] not in ('PROPOSED BATCH', 'ACTIONABLE RESUME') or not implementation_candidate(row, record):
            continue
        overlap_items.append({'id': str(row['number']), 'title': record['title'], 'brief': record['body'],
                              'fileSet': row['fileSet'], 'priority': record['priority'],
                              'createdAt': record['created_at'], 'branch': branch_identity(record),
                              'nextAction': 'implement' if row['action'] == 'implement' else 'resolve-development-pr'})
    if not overlap_items:
        return
    # Reuse the canonical plan/brief overlap classifier before lane allocation,
    # so a serialized loser cannot consume a cap and hide a feasible winner.
    with tempfile.TemporaryDirectory(prefix='workflow-scan-overlap-') as directory:
        path = Path(directory) / 'items.json'
        path.write_text(json.dumps({'items': overlap_items}))
        result = subprocess.run(['bash', str(SCRIPT_DIR / 'workflow-batch-overlap.sh'), '--input', str(path), '--json'],
                                text=True, capture_output=True)
        if result.returncode:
            raise ReadError(result.stderr.strip() or 'Snapshot overlap classification failed')
        overlap = json.loads(result.stdout)
    by_number = {row['number']: row for row in output}
    for group in overlap['serialGroups']:
        pairs = [pair for pair in overlap['pairs'] if pair['pairId'] in group['pairs']]
        for identity in group['itemIds']:
            row = by_number[int(identity)]
            row['overlapGroup'], row['overlapEvidence'] = group['groupId'], pairs
            if identity in group['heldItemIds']:
                row['category'], row['dispatch'] = 'HELD', 'held'
                row['reason'] = f'Overlap serialization with #{group["keepItemId"]}; held until prior item merges into approved base'


def snapshot_routing(record, action, root, selected):
    if record['status'] in TERMINAL:
        return None
    # Documentation stages belong to the hub. Implementation must use the
    # canonical ownership classifier, without fetching another repository.
    branches = [pr['branch'] for pr in record['prs']] or record['branches']
    implementation = ('feature/', 'fix/', 'refactor/', 'hotfix/')
    documentation = ('spec/', 'implementation-plan/')
    if record['prs'] and record['prs'][0]['branch'].startswith(documentation):
        return None
    if not (action in ('implement', 'run-code-review-and-open-pr', 'resolve-development-pr') or
            any(branch.startswith(implementation) for branch in branches)):
        return None
    config = configuration(root)
    mode = resolver.mode_from_shared(config, root / '.ai-dev-workflow.yaml')
    if mode != 'workflow_hub':
        return None
    return routing.classify(mode, 'implementation', str(record['number']),
                            routing.configured_keys_from_config(config),
                            [selected] if selected else [], record['type'] == 'Workflow')


def snapshot_classify(args):
    root = Path(args.repo_root).resolve()
    snapshot = snapshot_read(args.scan_snapshot, root)
    if args.mode == 'validate':
        return
    metadata = {}
    if os.environ.get('WORKFLOW_SCAN_LOCAL_METADATA_FILE'):
        path = Path(os.environ['WORKFLOW_SCAN_LOCAL_METADATA_FILE'])
        for line in path.read_text().splitlines():
            item = json.loads(line)
            if not isinstance(item, dict) or type(item.get('number')) is not int:
                raise ReadError('Malformed local classification metadata')
            metadata[item['number']] = item
    output = []
    records = {record['number']: record for record in snapshot['fullyRead']}
    today = datetime.now(timezone.utc).date()
    for record in sorted(snapshot['fullyRead'], key=lambda record: portfolio_sort_key(record, today)):
        if args.development and record.get('development_path') != args.development:
            continue
        if args.branch and args.branch not in record['branches']:
            continue
        if args.pr and not any(pr['number'] == args.pr for pr in record['prs']):
            continue
        category, action, reason = classify(record, snapshot)
        ownership = snapshot_routing(record, action, root, args.selected_repo)
        if ownership and (not ownership['continue_allowed'] or ownership['artifact_owner'] == 'selected_product_repository'):
            category = 'HELD'
            action = 'resolve-repository-selection' if not ownership['continue_allowed'] else 'hold-unreadable'
            reason = ownership['stop_reason'] or 'Product-owned implementation requires a bounded fresh read in the selected repository; hub snapshot evidence cannot authorize it'
        local_keys = ('toolFix', 'toolFixFiles', 'fileSet', 'localRuntime', 'developmentPath')
        local = {'toolFix': 'unknown', 'fileSet': 'unknown', 'localRuntime': 'none',
                 **{key: value for key, value in metadata.get(record['number'], {}).items() if key in local_keys}}
        if local['toolFix'] not in ('yes', 'no', 'unknown') or not isinstance(local['fileSet'], str):
            raise ReadError('Malformed local safety classification')
        output.append({'number': record['number'], 'category': category, 'action': action, 'reason': reason,
                       'priority': record['priority'], 'dueDate': record['due_date'], 'createdAt': record['created_at'], **local})
        if (action in ('write-plan', 'run-spec-review-and-open-pr', 'run-plan-review-and-open-pr') or record['status'] in ('Writing Spec', 'Writing Plan')) and output[-1]['toolFix'] == 'unknown':
            output[-1]['toolFix'] = 'no'
        if args.mode == 'next':
            if ownership:
                for key in ('outcome_code', 'display_label', 'continue_allowed', 'artifact_owner', 'selected_product_repo_key'):
                    print(f'ROUTING_{key.upper()}={str(ownership[key]).lower() if isinstance(ownership[key], bool) else ownership[key] or ""}')
            print(f'TARGET=issue:{record["number"]}\nSTATUS={record["status"]}\nNEXT_ACTION={action}\nCATEGORY={category}\nREASON={reason}')
    if args.mode == 'next' and len(output) != 1:
        raise ReadError('Target has no unique fully read scan record')
    if args.mode == 'batch':
        eligible = [row for row in output if row['category'] in ('PROPOSED BATCH', 'ACTIONABLE RESUME')]
        for index, row in enumerate(eligible):
            if row['dueDate'] and date.fromisoformat(row['dueDate']) <= today + timedelta(days=14) and any(PRIORITY_RANK.get(other['priority'].lower(), 2) < PRIORITY_RANK.get(row['priority'].lower(), 2) for other in eligible[index + 1:]):
                row['priorityWarning'] = f'Due date for #{row["number"]} conflicts with abstract Priority order; human attention required'
        batch_safety(output, records)
        blocks = []
        for row in output:
            if row['category'] not in ('PROPOSED BATCH', 'ACTIONABLE RESUME'):
                continue
            record = records[row['number']]
            category, action = row['category'], row['action']
            # Preserve canonical lane caps and portfolio report categorization.
            status = record['status']
            if status == 'Backlog' and category == 'ACTIONABLE RESUME':
                status = 'Writing Spec' if action == 'run-spec-review-and-open-pr' else 'Writing Plan' if action == 'run-plan-review-and-open-pr' else 'In Development'
            elif status == 'Backlog' and (record.get('spec') or record.get('plan')):
                status = 'Plan Ready' if record.get('plan') else 'Spec Ready'
            labels = ','.join(label for pr in record['prs'] for label in pr['labels'])
            if any(c in labels for c in '\r\n'):
                raise ReadError('Malformed PR label evidence')
            local_runtime = row['localRuntime']
            if local_runtime not in ('none', 'exclusive'):
                raise ReadError('Malformed local runtime classification')
            blocks.append(f'SLUG={record["number"]}\nSTATUS={status}\nNEXT_ACTION={action}\nLABELS={labels}\nLOCAL_RUNTIME={local_runtime}\n')
        if blocks:
            result = subprocess.run(['bash', str(SCRIPT_DIR / 'workflow-batch-lanes.sh'), '--repo-root', str(root)],
                                    input='\n'.join(blocks), text=True, capture_output=True)
            if result.returncode:
                raise ReadError(result.stderr.strip() or 'Snapshot lane classification failed')
            by_number = {row['number']: row for row in output}
            for block in result.stdout.split('\n\n'):
                values = dict(line.split('=', 1) for line in block.splitlines() if '=' in line)
                if values.get('SLUG', '').isdigit() and 'REPORT_LABEL' in values:
                    row = by_number[int(values['SLUG'])]
                    row['category'] = values['REPORT_LABEL'].split(' - ')[0]
                    row['reportLabel'] = values['REPORT_LABEL']
                    row['dispatch'] = values.get('DISPATCH', '')
                    row['stageLane'] = values.get('STAGE_LANE', '')
                    if row['category'] == 'HELD':
                        row['reason'] = values.get('HOLD_REASON') or row['reason']
        print(json.dumps(output))


def scan(args):
    root = Path(args.repo_root).resolve()
    config = configuration(root)
    tracker = config.get('issue_tracker') or {}
    if tracker.get('provider') != 'github_projects':
        raise ReadError('Portfolio coordinator requires github_projects; other providers retain Protocol 90')
    repo = repository(root)
    owner, project_number = tracker_scope(config, repo)
    client = reader.Client(strict_cost=True)
    warnings = []
    reserve = reserve_from_config(config, warnings)
    before = budget(client)
    coverage, reason = FULL, 'GraphQL budget sufficient'
    report = {'repo': repo, 'projectOwner': owner, 'projectNumber': project_number, 'invocation': uuid.uuid4().hex,
              'framework': (config.get('template') or {}).get('is_template') is True,
              'fullyRead': [], 'omissions': [], 'openIdentities': [], 'reserve': reserve,
              'projectionCeiling': P, 'targetBound': Q, 'warnings': warnings}
    rejection = False
    error = None
    pending = []
    tracker_evidence = {}

    def publish_dependencies():
        for record in pending:
            if all(n in tracker_evidence for n in record['dependencies']):
                record['dependencyStates'] = {str(n): tracker_evidence[n] for n in record['dependencies']}
                report['fullyRead'].append(record)
            else:
                report['omissions'].append({'number': record['number'], 'reason': 'Dependency tracker state unreadable in this invocation; bounded reconciliation required'})
        pending.clear()
    if before is None:
        warnings.append('GraphQL budget could not be read')
        reason = 'GraphQL budget could not be read'
    if before is not None and before['remaining'] < P + reserve:
        coverage, reason = DEFERRED, 'GraphQL budget too low to scan'
    else:
        try:
            client.allowance = P
            project = project_id(client, owner, int(project_number))
            report['projectId'] = project
            issues = client.rest(f'repos/{repo}/issues?state=open&per_page=100', paginate=True)
            prs = client.rest(f'repos/{repo}/pulls?state=open&per_page=100', paginate=True)
            identities = {}
            for issue in issues:
                if not isinstance(issue, dict) or type(issue.get('number')) is not int or not isinstance(issue.get('title'), str) or issue.get('state') != 'open':
                    raise ReadError('Incomplete current issue enumeration')
                if 'pull_request' not in issue:
                    identities[issue['number']] = issue
            folders, branches = current_local_evidence(root)
            for pr in prs:
                if not isinstance(pr, dict) or not isinstance(pr.get('head'), dict):
                    raise ReadError('Incomplete current PR enumeration')
            full = sorted(identities)
            inflight = set(folders) | set(branches) | {issue_number(pr['head'].get('ref', '')) for pr in prs}
            partial = [n for n in full if n in inflight]
            report['openIdentities'] = full
            full_cost, partial_cost = client.spent + Q * len(full), client.spent + Q * len(partial)
            report['projectionSpend'] = client.spent
            report['fullCost'], report['partialCost'] = full_cost, min(full_cost, partial_cost)
            if before is not None:
                if before['remaining'] >= full_cost + reserve:
                    coverage = FULL
                elif before['remaining'] >= partial_cost + reserve:
                    coverage, reason = PARTIAL, 'GraphQL budget too low for a full scan'
                else:
                    coverage, reason = DEFERRED, 'GraphQL budget too low to scan'
                client.allowance = before['remaining'] - reserve
            else:
                client.allowance = None
            selected = full if coverage == FULL else partial if coverage == PARTIAL else []
            report['omissions'] = [{'number': n, 'reason': 'Backlog discovery skipped (budget-limited)'} for n in full if n not in selected]
            type_field = (tracker.get('custom_fields') or {}).get('type_field', '')
            for index, number in enumerate(selected):
                try:
                    start = client.spent
                    card = reader.target(client, number, project, repo, type_field, strict_dependencies=True)
                    if client.spent - start > Q:
                        raise ReadError('Target query reservation exceeded')
                    if card.get('status') and card.get('type'):
                        tracker_evidence[number] = card['status']
                    record = complete_record(client, repo, identities[number], card, folders, branches, prs, root)
                    # Publication occurs only after tracker and required REST evidence complete.
                    if record['dependencies']:
                        pending.append(record)
                    else:
                        report['fullyRead'].append(record)
                except ReadError as exc:
                    report['omissions'].append({'number': number, 'reason': str(exc)})
                    if isinstance(exc, EvidenceIncomplete):
                        continue
                    if rate_limited(exc):
                        report['omissions'] += [{'number': n, 'reason': 'Not read after rate-limit rejection'} for n in selected[index + 1:]]
                        raise
                    raise
            publish_dependencies()
        except ReadError as exc:
            publish_dependencies()
            if rate_limited(exc):
                rejection = True
                coverage = PARTIAL if report['fullyRead'] else DEFERRED
                reason = 'GraphQL budget ran out during the scan'
            else:
                error = str(exc)
    report['coverage'], report['reason'] = coverage, reason
    report['ledger'] = client.ledger
    report['scanOwnedSpend'] = client.spent
    after = budget(client)
    spent = 'Unavailable'
    remaining, reset = 'Unavailable', 'Unavailable'
    if after is not None:
        remaining = after['remaining']
        reset = datetime.fromtimestamp(after['reset'], timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
        if before is not None:
            spent = 'Unavailable (budget reset during scan)' if after['reset'] != before['reset'] or after['remaining'] > before['remaining'] else before['remaining'] - after['remaining']
        if coverage != DEFERRED and not rejection and after['remaining'] < reserve:
            warnings.append('GraphQL budget below reserve after scan; other consumers on the same account may have spent budget during the scan')
    else:
        if 'GraphQL budget could not be read' not in warnings:
            warnings.append('GraphQL budget could not be read')
    report['spend'] = {'GraphQL points spent by this scan': spent, 'GraphQL points remaining': remaining, 'GraphQL budget resets at': reset}
    report['spendNote'] = 'Observed spend may include spending by other consumers on the same account.'
    report['skipped'] = 'Backlog discovery skipped' if coverage == PARTIAL else 'No proposal' if coverage == DEFERRED else ''
    report['classification'] = []
    if error:
        report['error'] = error
    elif coverage != DEFERRED:
        with tempfile.TemporaryDirectory(prefix='workflow-scan-') as directory:
            path = Path(directory) / 'snapshot.json'
            path.write_text(json.dumps(report))
            env = os.environ.copy()
            env['WORKFLOW_SCAN_INVOCATION_ID'] = report['invocation']
            paths = [record['development_path'] for record in report['fullyRead'] if record.get('development_path')]
            result = subprocess.run(['bash', str(SCRIPT_DIR / 'workflow-batch-plan.sh'), '--repo-root', str(root), '--scan-snapshot', str(path), *paths], env=env, text=True, capture_output=True)
            if result.returncode:
                raise ReadError(result.stderr.strip() or 'Scan classifier failed')
            report['classification'] = json.loads(result.stdout)
            warnings.extend(row['priorityWarning'] for row in report['classification'] if row.get('priorityWarning'))
    proposed = [row['number'] for row in report['classification'] if row['category'] == 'PROPOSED BATCH']
    report['recommendedCommand'] = ('/run-items ' + ' '.join(map(str, proposed))) if len(proposed) >= 2 else ('/run-item ' + str(proposed[0])) if proposed else ''
    if args.json:
        print(json.dumps(report))
    else:
        print(f'Scan coverage: {coverage}\nReason: {reason}')
        for label, value in report['spend'].items():
            print(f'{label}: {value}')
        print(report['spendNote'])
        for warning in warnings:
            print('WARNING: ' + warning)
        if report['skipped']:
            print(report['skipped'])
        for row in report['classification']:
            labels = {'INFORMATIONAL': 'INFORMATIONAL - not actionable in this proposal', 'ACTIONABLE RESUME': 'ACTIONABLE RESUME - can advance now', 'PROPOSED BATCH': 'PROPOSED BATCH - your decision', 'HELD': 'HELD - not included in proposed batch'}
            print(f'{row.get("reportLabel", labels[row["category"]])}: #{row["number"]} — {row["action"]} — {row["reason"]}')
        for omission in report['omissions']:
            print(f'HELD - not included in proposed batch: #{omission["number"]} — {omission["reason"]}')
        if report['recommendedCommand']:
            print('Recommended command: ' + report['recommendedCommand'])
        if error:
            print('Tracker unavailable: ' + error, file=sys.stderr)
    return 1 if error else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo-root', default=str(SCRIPT_DIR.parent.parent))
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--scan-snapshot')
    parser.add_argument('--mode', choices=('batch', 'next', 'validate'), default='batch')
    parser.add_argument('--repo', dest='selected_repo')
    parser.add_argument('--development')
    parser.add_argument('--branch')
    parser.add_argument('--pr', type=int)
    parser.add_argument('paths', nargs='*')
    args = parser.parse_args()
    try:
        if args.scan_snapshot:
            snapshot_classify(args)
            return 0
        return scan(args)
    except (ReadError, resolver.ConfigError, OSError, ValueError, TypeError, AttributeError, KeyError) as exc:
        print('Tracker unavailable: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
