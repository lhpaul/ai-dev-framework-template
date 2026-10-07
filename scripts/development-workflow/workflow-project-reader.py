#!/usr/bin/env python3
"""Bounded project-card queries shared by target commands and portfolio scans."""
import argparse
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

FIELDS = '''id
  content { ... on Issue { number url repository { nameWithOwner } issueType { name } } }
  dependsOn: fieldValueByName(name:"DependsOn") { ... on ProjectV2ItemFieldTextValue { text } }
  dependencies: fieldValueByName(name:"Dependencies") { ... on ProjectV2ItemFieldTextValue { text } }
  status: fieldValueByName(name:"Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  configuredType: fieldValueByName(name:$typeFieldName) { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  customType: fieldValueByName(name:"Custom Type") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  compactCustomType: fieldValueByName(name:"CustomType") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  type: fieldValueByName(name:"Type") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  priority: fieldValueByName(name:"Priority") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  dueDate: fieldValueByName(name:"Due date") { ... on ProjectV2ItemFieldDateValue { date } }
  size: fieldValueByName(name:"Size") { ... on ProjectV2ItemFieldSingleSelectValue { name } }'''
PRIMARY = '''query($owner:String!,$repo:String!,$issueNumber:Int!,$typeFieldName:String!,$after:String) {
 repository(owner:$owner,name:$repo) { issue(number:$issueNumber) {
 projectItems(first:100,after:$after,includeArchived:true) { nodes { project { id number } %s }
 pageInfo { hasNextPage endCursor } } } } rateLimit { cost } }''' % FIELDS
FALLBACK = '''query($projectId:ID!,$selector:String!,$typeFieldName:String!) {
 node(id:$projectId) { ... on ProjectV2 { items(first:100,query:$selector,archivedStates:[ARCHIVED,NOT_ARCHIVED]) {
 nodes { %s } pageInfo { hasNextPage endCursor } } } } rateLimit { cost } }''' % FIELDS


class ReadError(RuntimeError):
    def __init__(self, message, errors=None):
        super().__init__(message)
        self.errors = errors or []


class Client:
    """All requests go through gh; tests replace that executable, never forward."""
    def __init__(self, strict_cost=False, allowance=None):
        self.strict_cost = strict_cost
        self.allowance = allowance
        self.spent = 0
        self.ledger = []

    def call(self, args, graphql_errors=False):
        result = subprocess.run(['gh', *args], text=True, capture_output=True)
        if result.returncode:
            # gh exits 1 for GraphQL errors while still emitting the typed
            # payload needed to distinguish a user-owner NOT_FOUND or quota
            # rejection. REST/transport/auth failures never enter this path.
            if graphql_errors:
                try:
                    payload = json.loads(result.stdout)
                    errors = payload.get('errors') if isinstance(payload, dict) else None
                    if isinstance(errors, list) and errors and all(isinstance(error, dict) for error in errors):
                        return payload
                except (ValueError, TypeError):
                    pass
            raise ReadError(result.stderr.strip() or 'GitHub read failed')
        try:
            return json.loads(result.stdout)
        except (ValueError, TypeError) as exc:
            raise ReadError('Malformed GitHub read response') from exc

    def rest(self, endpoint, paginate=False):
        args = ['api']
        if paginate:
            args += ['--paginate', '--slurp']
        data = self.call([*args, endpoint])
        if paginate:
            if not isinstance(data, list) or any(not isinstance(page, list) for page in data):
                raise ReadError('Incomplete REST enumeration')
            return [item for page in data for item in page]
        return data

    def graphql(self, query_text, **variables):
        if self.allowance is not None and self.spent + 1 > self.allowance:
            raise ReadError('GraphQL query reservation exceeded')
        entry = {'query': query_text, 'variables': variables, 'reserved': 1}
        self.ledger.append(entry)
        # Reserve every attempted request, including partial/error responses.
        self.spent += 1
        args = ['api', 'graphql', '-f', 'query=' + query_text]
        for key, value in variables.items():
            if value is not None:
                args += ['-F' if type(value) is int else '-f', f'{key}={value}']
        response = self.call(args, graphql_errors=True)
        if not isinstance(response, dict):
            raise ReadError('Malformed GraphQL response')
        data = response.get('data')
        rate = data.get('rateLimit') if isinstance(data, dict) else None
        if rate is not None and not isinstance(rate, dict):
            raise ReadError('Malformed GraphQL rateLimit evidence')
        cost = (rate or {}).get('cost')
        entry['charged'] = cost if type(cost) is int else 1
        if any(isinstance(error, dict) and error.get('type') == 'RATE_LIMITED' for error in response.get('errors') or []):
            raise ReadError(json.dumps(response['errors']), response['errors'])
        # Partial responses can include cost evidence: validate it before any
        # NOT_FOUND fallback, while preserving unreadable rate-limit errors.
        if self.strict_cost and (rate is not None or not response.get('errors')) and (type(cost) is not int or cost != 1):
            raise ReadError('GraphQL cost contract changed: expected 1, received ' + repr(cost))
        # Failed/partial GraphQL responses never establish absence.
        if response.get('errors'):
            raise ReadError(json.dumps(response['errors']), response['errors'])
        if not isinstance(data, dict):
            raise ReadError('Missing GraphQL data')
        return data


def connection(value):
    if not isinstance(value, dict) or not isinstance(value.get('nodes'), list):
        raise ReadError('Missing project connection')
    info = value.get('pageInfo')
    if not isinstance(info, dict) or type(info.get('hasNextPage')) is not bool:
        raise ReadError('Missing project pagination evidence')
    if info['hasNextPage'] and (not isinstance(info.get('endCursor'), str) or not info['endCursor']):
        raise ReadError('Missing project pagination cursor')
    if any(not isinstance(item, dict) for item in value['nodes']):
        raise ReadError('Malformed project candidate')
    return value['nodes'], info


def compact(item, project_id, preferred, strict_dependencies=False):
    content = item.get('content')
    if content is not None and not isinstance(content, dict):
        raise ReadError('Malformed project content identity')
    candidates = ([item.get('configuredType')] if preferred else []) + [
        (content or {}).get('issueType'), item.get('customType'),
        item.get('compactCustomType'), item.get('type')]
    def name(value):
        return value.get('name', '') if isinstance(value, dict) and isinstance(value.get('name', ''), str) else ''
    if not isinstance(item.get('id'), str) or not item['id']:
        raise ReadError('Missing project item identity')
    due = item.get('dueDate')
    if due is not None and (not isinstance(due, dict) or (due.get('date') is not None and not isinstance(due['date'], str))):
        raise ReadError('Malformed Due date evidence')
    due_date = (due or {}).get('date') or ''
    if due_date:
        try:
            date.fromisoformat(due_date)
        except ValueError as exc:
            raise ReadError('Malformed Due date evidence') from exc
    dependencies = []
    for field in ('dependsOn', 'dependencies'):
        value = item.get(field)
        if value is None:
            continue
        if not isinstance(value, dict) or ('text' in value and value['text'] is not None and not isinstance(value['text'], str)):
            raise ReadError('Malformed dependency field evidence')
        # A nullable Text value is empty. A different configured field type
        # produces an empty fragment: membership callers may still read it,
        # but a scan cannot claim complete dependency evidence from it.
        if 'text' not in value and strict_dependencies:
            raise ReadError('Unknown dependency field type')
        dependencies.append(value.get('text') or '')
    return {'item_id': item['id'], 'project_id': project_id,
            'status': name(item.get('status') or item.get('fieldValueByName')),
            'type': next((name(c) for c in candidates if name(c)), ''),
            'priority': name(item.get('priority')), 'size': name(item.get('size')),
            'due_date': due_date,
            'depends_on': ' '.join(dependencies)}


def selector(repo, issue):
    title = issue.get('title')
    if not isinstance(title, str) or not title or any(ord(c) < 32 for c in title):
        raise ReadError('Target title cannot be safely represented in project filter')
    escaped = title.replace('\\', '\\\\').replace('"', '\\"')
    return f'repo:{repo} is:issue ' + ('is:open ' if issue.get('state') == 'open' else '') + f'"{escaped}"'


def valid_cached_result(value, project_id):
    if not isinstance(value, dict) or value.get('project_id') != project_id:
        return False
    if value.get('membership') == 'absent':
        return set(value) == {'membership', 'project_id'}
    keys = {'item_id', 'project_id', 'status', 'type', 'priority', 'size', 'due_date', 'depends_on'}
    if set(value) != keys or any(not isinstance(value[key], str) for key in keys) or not value['item_id']:
        return False
    try:
        if value['due_date']:
            date.fromisoformat(value['due_date'])
    except ValueError:
        return False
    return True


def fallback(client, number, project_id, repo, preferred='', cache_dir=None, cache_pid=None, ttl=5, strict_dependencies=False):
    issue = client.rest(f'repos/{repo}/issues/{number}')
    if not isinstance(issue, dict) or issue.get('number') != number or 'pull_request' in issue:
        raise ReadError('Fresh target issue identity unavailable')
    query = selector(repo, issue)
    cache_file = None
    if cache_dir and cache_pid and ttl > 0:
        folder = Path(cache_dir)
        if folder.is_dir() and not folder.is_symlink() and folder.stat().st_uid == os.getuid() and folder.stat().st_mode & 0o077 == 0:
            key = hashlib.sha256(json.dumps([repo.lower(), project_id, number, preferred, query, 'both-archived', strict_dependencies]).encode()).hexdigest()
            cache_file = folder / f'{cache_pid}-{key}.json'
            if cache_file.is_file() and not cache_file.is_symlink() and time.time() - cache_file.stat().st_mtime < ttl * 60:
                try:
                    cached = json.loads(cache_file.read_text())
                    if valid_cached_result(cached, project_id):
                        return cached
                except ValueError:
                    pass
    data = client.graphql(FALLBACK, projectId=project_id, selector=query, typeFieldName=preferred)
    node = data.get('node')
    if not isinstance(node, dict):
        raise ReadError('Missing project node')
    nodes, info = connection(node.get('items'))
    matches = []
    for item in nodes:
        content = item.get('content') or {}
        if not isinstance(content, dict) or (content.get('repository') is not None and not isinstance(content.get('repository'), dict)):
            raise ReadError('Malformed project content identity')
        identity = (content.get('repository') or {}).get('nameWithOwner')
        if type(content.get('number')) is not int or not isinstance(identity, str) or not identity:
            raise ReadError('Missing project content identity; membership unknown')
        if content.get('number') == number and isinstance(identity, str) and identity.lower() == repo.lower():
            matches.append(compact(item, project_id, preferred, strict_dependencies))
    if len(matches) > 1 and any(item != matches[0] for item in matches[1:]):
        raise ReadError('Conflicting exact project-card identities')
    if matches:
        result = matches[0]
    elif info['hasNextPage']:
        raise ReadError('Bounded project candidate cap reached; membership unknown (restore/reconcile if archived)')
    else:
        result = {'membership': 'absent', 'project_id': project_id}
    if cache_file:
        # Private atomic publication; failed/unreadable results never cached.
        for old in cache_file.parent.iterdir():
            if old.is_file() and not old.is_symlink() and (old.suffix == '.json' or old.name.startswith('.item-list.')) and time.time() - old.stat().st_mtime > 3600:
                old.unlink()
        fd, tmp = tempfile.mkstemp(prefix='.item-list.', dir=cache_file.parent)
        try:
            with os.fdopen(fd, 'w') as stream:
                json.dump(result, stream)
            os.replace(tmp, cache_file)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    return result


def target(client, number, project_id, repo, preferred='', strict_dependencies=False):
    owner, name = repo.split('/')
    cursor = None
    seen = set()
    for _ in range(20):
        data = client.graphql(PRIMARY, owner=owner, repo=name, issueNumber=number, typeFieldName=preferred, after=cursor)
        repository_value = data.get('repository')
        if not isinstance(repository_value, dict):
            raise ReadError('Missing repository evidence')
        issue = repository_value.get('issue')
        if not isinstance(issue, dict):
            raise ReadError('Target issue unavailable')
        nodes, info = connection(issue.get('projectItems'))
        matches = [compact(item, project_id, preferred, strict_dependencies) for item in nodes if isinstance(item.get('project'), dict) and item['project'].get('id') == project_id]
        if matches:
            if any(item != matches[0] for item in matches[1:]):
                raise ReadError('Conflicting exact project-card identities')
            return matches[0]
        if not info['hasNextPage']:
            return fallback(client, number, project_id, repo, preferred, strict_dependencies=strict_dependencies)
        cursor = info['endCursor']
        if cursor in seen:
            raise ReadError('Repeated project pagination cursor')
        seen.add(cursor)
    raise ReadError('Project membership pagination cap reached; membership unknown')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fallback', action='store_true')
    parser.add_argument('--number', type=int, required=True)
    parser.add_argument('--project-id', required=True)
    parser.add_argument('--repo', required=True)
    parser.add_argument('--type-field', default='')
    parser.add_argument('--cache-dir')
    parser.add_argument('--cache-pid')
    parser.add_argument('--ttl', type=int, default=5)
    args = parser.parse_args()
    try:
        result = fallback(Client(), args.number, args.project_id, args.repo, args.type_field,
                          args.cache_dir, args.cache_pid, args.ttl)
        print(json.dumps(result, separators=(',', ':')))
    except (ReadError, OSError, ValueError, TypeError, AttributeError) as exc:
        print('Warning: bounded item-list fallback failed; tracker status not read: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
