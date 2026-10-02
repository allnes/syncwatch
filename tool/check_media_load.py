#!/usr/bin/env python3
"""Validate JSONL evidence from synthetic_media_load.dart (Python standard library)."""
import argparse
import json
from pathlib import Path


def check_streams(rows, minimum_seconds):
    streams, failures = {}, []
    for direction, kind, report_type, counter in [
        ('send', 'video', 'outbound-rtp', 'framesEncoded'),
        ('receive', 'video', 'inbound-rtp', 'framesDecoded'),
        ('send', 'audio', 'media-source', 'totalAudioEnergy'),
        ('receive', 'audio', 'inbound-rtp', 'totalAudioEnergy'),
    ]:
        reports = [row for row in rows if row.get('direction') == direction
                   and row.get('reportType') == report_type
                   and row.get('values', {}).get('kind') == kind]
        # A track may restart. Evaluate each native report independently.
        groups = {}
        for row in reports:
            groups.setdefault(row['reportId'], []).append(row)
        valid = []
        for group in groups.values():
            first, last = group[0], group[-1]
            seconds = (last['elapsedMs'] - first['elapsedMs']) / 1000
            delta = last['values'].get(counter, 0) - first['values'].get(counter, 0)
            if seconds >= minimum_seconds and delta > (120 if kind == 'video' else 0):
                summary = {'seconds': round(seconds, 2), 'counterDelta': delta}
                if kind == 'video':
                    summary['averageFps'] = round(delta / seconds, 2)
                    summary['implementation'] = last['values'].get(
                        'encoderImplementation' if direction == 'send' else 'decoderImplementation')
                valid.append(summary)
        key = f'{direction}_{kind}'
        streams[key] = valid
        if not valid:
            failures.append(f'{key}: no sustained nonzero media')
    return streams, failures


def check(path, require_restart=False):
    rows = [json.loads(line) for line in path.read_text(encoding='utf-8-sig').splitlines()]
    failures = []
    if any(row['type'] in ('fatal', 'statsError') for row in rows):
        failures.append('runtime/statistics error')
    if not any(row['type'] == 'finished' for row in rows):
        failures.append('no clean finish')
    if not any(row['type'] == 'mediaStopped' and row['localTracks'] == 0 for row in rows):
        failures.append('published media not released')
    streams, stream_failures = check_streams(rows, 20 if require_restart else 30)
    failures.extend(stream_failures)
    result = {'file': path.name, 'streams': streams}
    if require_restart:
        stopped = [r for r in rows if r['type'] == 'cycleStopped']
        restarted = [r for r in rows if r['type'] == 'cycleRestarted']
        if (len(stopped) != 1 or len(restarted) != 1
                or stopped[0]['localTracks'] != 0 or restarted[0]['localTracks'] != 2
                or stopped[0]['elapsedMs'] >= restarted[0]['elapsedMs']):
            failures.append('expected one ordered media restart with 0 then 2 tracks')
        else:
            result['restart'] = {}
            for phase, segment in [
                ('before', [r for r in rows if r['elapsedMs'] < stopped[0]['elapsedMs']]),
                ('after', [r for r in rows if r['elapsedMs'] > restarted[0]['elapsedMs']]),
            ]:
                segment_streams, segment_failures = check_streams(segment, 20)
                result['restart'][phase] = segment_streams
                failures.extend(f'{phase} restart: {failure}' for failure in segment_failures)
            before = [r for r in rows if r['type'] == 'playback'
                      and r['elapsedMs'] < stopped[0]['elapsedMs']]
            after = [r for r in rows if r['type'] == 'playback'
                     and r['elapsedMs'] > restarted[0]['elapsedMs']]
            if not before or not after or after[0]['positionMs'] <= before[-1]['positionMs']:
                failures.append('movie did not advance across media restart')
    positions = [row['positionMs'] for row in rows if row['type'] == 'playback']
    if not positions or max(positions) - min(positions) < 20000:
        failures.append('movie did not advance at least 20 seconds')
    result['syncCommands'] = sorted({row['command']['type'] for row in rows if row['type'] == 'sync'})
    result['failures'] = failures
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('logs', nargs='+', type=Path)
    parser.add_argument('--require-restart', action='store_true',
                        help='Require 20 seconds of real media both before and after one call restart')
    args = parser.parse_args()
    results = [check(path, args.require_restart) for path in args.logs]
    print(json.dumps(results, indent=2))
    return int(any(result['failures'] for result in results))


if __name__ == '__main__':
    raise SystemExit(main())
