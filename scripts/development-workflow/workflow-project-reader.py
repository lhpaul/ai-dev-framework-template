#!/usr/bin/env python3
"""Bounded project-card queries shared by target commands and portfolio scans."""
import argparse
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
  status: fieldValueByName(name:"Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  configuredType: fieldValueByName(name:$typeFieldName) { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  customType: fieldValueByName(name:"Custom Type") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  compactCustomType: fieldValueByName(name:"CustomType") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  type: fieldValueByName(name:"Type") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  priority: fieldValueByName(name:"Priority") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  size: fieldValueByName(name:"Size") { ... on ProjectV2ItemFieldSingleSelectValue { name } }'''
PRIMARY = '''query($owner:String!,$repo:String!,$issueNumber:Int!,$typeFieldName:String!,$after:String) {
 repository(owner:$owner,name:$repo) { issue(number:$issueNumber) {
 projectItems(first:100,after:$after,includeArchived:true) { nodes { project { id number } %s }
 pageInfo { hasNextPage endCursor } } } } rateLimit { cost } }''' % FIELDS
FALLBACK = '''query($projectId:ID!,$query:String!,$typeFieldName:String!) {
 node(id:$projectId) { ... on ProjectV2 { items(first:100,query:$query,archivedStates:[ARCHIVED,NOT_ARCHIVED]) {
 nodes { %s } pageInfo { hasNextPage endCursor } } } } rateLimit { cost } }''' % FIELDS


class ReadError(RuntimeError):
    pass


class Client:
    """All requests go through gh; tests replace that executable, never forward."""
    def __init__(self, strict_cost=False, allowance=None):
        self.strict_cost = strict_cost
        self.allowance = allowance
        self.spent = 0
        self.ledger = []

    def call(self, args):
        result = subprocess.run(['gh', *args], text=True, capture_output=True)
        if result.returncode:
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
        args = ['api', 'graphql', '-f', 'query=' + query_text]
        for key, value in variables.items():
            if value is not None:
                args += ['-F' if type(value) is int else '-f', f'{key}={value}']
        response = self.call(args)
        # Failed/partial GraphQL responses never establish absence.
        if not isinstance(response, dict) or response.get('errors'):
            raise ReadError(json.dumps(response.get('errors') if isinstance(response, dict) else response))
        data = response.get('data')
        if not isinstance(data, dict):
            raise ReadError('Missing GraphQL data')
        cost = (data.get('rateLimit') or {}).get('cost')
        if self.strict_cost and (type(cost) is not int or cost != 1):
            raise ReadError('GraphQL cost contract changed: expected 1, received ' + repr(cost))
        self.spent += 1
        entry['charged'] = cost if type(cost) is int else 1
        return data


def connection(value):
    if not isinstance(value, dict) or not isinstance(value.get('nodes'), list):
        raise ReadError('Missing project connection')
    info = value.get('pageInfo')
    if not isinstance(info, dict) or type(info.get('hasNextPage')) is not bool:
        raise ReadError('Missing project pagination evidence')
    if info['hasNextPage'] and not info.get('endCursor'):
        raise ReadError('Missing project pagination cursor')
    if any(not isinstance(item, dict) for item in value['nodes']):
        raise ReadError('Malformed project candidate')
    return value['nodes'], info


def compact(item, project_id, preferred):
    content = item.get('content')
    if content is not None and not isinstance(content, dict):
        raise ReadError('Malformed project content identity')
    candidates = ([item.get('configuredType')] if preferred else []) + [
        (content or {}).get('issueType'), item.get('customType'),
        item.get('compactCustomType'), item.get('type')]
    def name(value):
        return value.get('name', '') if isinstance(value, dict) else ''
    return {'item_id': item.get('id') or '', 'project_id': project_id,
            'status': name(item.get('status') or item.get('fieldValueByName')),
            'type': next((name(c) for c in candidates if name(c)), ''),
            'priority': name(item.get('priority')), 'size': name(item.get('size'))}


def selector(repo, issue):
    title = issue.get('title')
    if not isinstance(title, str) or not title or any(ord(c) < 32 for c in title):
        raise ReadError('Target title cannot be safely represented in project filter')
    escaped = title.replace('\\', '\\\\').replace('"', '\\"')
    return f'repo:{repo} is:issue ' + ('is:open ' if issue.get('state') == 'open' else '') + f'"{escaped}"'


def fallback(client, number, project_id, repo, preferred='', cache_dir=None, cache_pid=None, ttl=5):
    issue = client.rest(f'repos/{repo}/issues/{number}')
    if not isinstance(issue, dict) or issue.get('number') != number or 'pull_request' in issue:
        raise ReadError('Fresh target issue identity unavailable')
    query = selector(repo, issue)
    cache_file = None
    if cache_dir and cache_pid and ttl > 0:
        folder = Path(cache_dir)
        if folder.is_dir() and not folder.is_symlink() and folder.stat().st_uid == os.getuid():
            key = hashlib.sha256(json.dumps([repo.lower(), project_id, number, preferred, query, 'both-archived']).encode()).hexdigest()
            cache_file = folder / f'{cache_pid}-{key}.json'
            if cache_file.is_file() and not cache_file.is_symlink() and time.time() - cache_file.stat().st_mtime < ttl * 60:
                try:
                    cached = json.loads(cache_file.read_text())
                    if isinstance(cached, dict) and cached.get('project_id') == project_id and (cached.get('item_id') or cached.get('membership') == 'absent'):
                        return cached
                except ValueError:
                    pass
    data = client.graphql(FALLBACK, projectId=project_id, query=query, typeFieldName=preferred)
    nodes, info = connection((data.get('node') or {}).get('items'))
    matches = []
    for item in nodes:
        content = item.get('content') or {}
        if not isinstance(content, dict) or (content.get('repository') is not None and not isinstance(content.get('repository'), dict)):
            raise ReadError('Malformed project content identity')
        identity = (content.get('repository') or {}).get('nameWithOwner')
        if content.get('number') == number and isinstance(identity, str) and identity.lower() == repo.lower():
            matches.append(compact(item, project_id, preferred))
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


def target(client, number, project_id, repo, preferred=''):
    owner, name = repo.split('/')
    cursor = None
    seen = set()
    for _ in range(20):
        data = client.graphql(PRIMARY, owner=owner, repo=name, issueNumber=number, typeFieldName=preferred, after=cursor)
        issue = (data.get('repository') or {}).get('issue')
        if not isinstance(issue, dict):
            raise ReadError('Target issue unavailable')
        nodes, info = connection(issue.get('projectItems'))
        matches = [compact(item, project_id, preferred) for item in nodes if (item.get('project') or {}).get('id') == project_id]
        if matches:
            if any(item != matches[0] for item in matches[1:]):
                raise ReadError('Conflicting exact project-card identities')
            return matches[0]
        if not info['hasNextPage']:
            return fallback(client, number, project_id, repo, preferred)
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
    except (ReadError, OSError, ValueError) as exc:
        print('Warning: bounded item-list fallback failed; tracker status not read: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
