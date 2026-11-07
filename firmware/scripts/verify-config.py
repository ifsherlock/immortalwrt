#!/usr/bin/env python3
import pathlib
import re
ROOT=pathlib.Path(__file__).resolve().parents[2]
def parse(text):
    result={}
    for line in text.splitlines():
        if line.startswith('CONFIG_') and '=' in line:
            k,v=line.split('=',1); result[k]=v
        elif re.fullmatch(r'# CONFIG_\S+ is not set',line):
            result[line.split()[1]]='n'
    return result
actual=parse((ROOT/'.config').read_text())
expected={}
for p in ['firmware/pve-x86.config','firmware/fragments/honk.config']:
    expected.update(parse((ROOT/p).read_text()))
errors=[f'{k}: expected {v}, got {actual.get(k,"<missing>")}' for k,v in expected.items() if (actual.get(k,'n') if v=='n' else actual.get(k))!=v]
if errors:
    raise SystemExit('Configuration selections were not honored:\n'+'\n'.join(errors))
print(f'Validated {len(expected)} requested configuration settings.')
