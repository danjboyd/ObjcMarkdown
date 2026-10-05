#!/usr/bin/env python3
"""Usage: restore-eol.py FILE...

Some sources mix CRLF and LF line by line (OMMarkdownRenderer.m, its tests,
some GNUmakefiles, AGENTS.md). Editors and scripts often rewrite a whole
file with one ending, turning a small change into a diff of every line.
This puts each unchanged line's ending back as it is in HEAD, and gives
changed or new lines the ending of the nearest unchanged line before them.
Check afterwards: `git diff --stat` should equal
`git diff HEAD --ignore-cr-at-eol --stat`.
"""
import difflib
import subprocess
import sys


def split_keep(data):
    lines = data.split(b"\n")
    out = [l + b"\n" for l in lines[:-1]]
    if lines[-1]:
        out.append(lines[-1])
    return out


def restore(path):
    head = subprocess.run(["git", "show", "HEAD:" + path], capture_output=True)
    if head.returncode != 0:
        print(path, "not in HEAD, skipped")
        return
    old = split_keep(head.stdout)
    new = split_keep(open(path, "rb").read())
    strip = lambda l: l.rstrip(b"\r\n")
    matcher = difflib.SequenceMatcher(None, [strip(l) for l in old], [strip(l) for l in new], autojunk=False)
    result = []
    ending = b"\n"
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        for k in range(j2 - j1):
            line = new[j1 + k]
            body = strip(line)
            terminated = line.endswith(b"\n")
            if tag == "equal":
                src = old[i1 + k]
                ending = b"\r\n" if src.endswith(b"\r\n") else b"\n"
            result.append(body + (ending if terminated else b""))
    open(path, "wb").write(b"".join(result))
    print(path, "restored")


for p in sys.argv[1:]:
    restore(p)
