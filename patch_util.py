import re
def patch(path, pairs):
    raw=open(path,"rb").read().decode("utf-8-sig"); crlf="\r\n" in raw
    s=raw.replace("\r\n","\n")
    for old,new in pairs:
        n=s.count(old)
        assert n==1, f"{path}: {n} matches for {old[:70]!r}"
        s=s.replace(old,new)
    if crlf: s=s.replace("\n","\r\n")
    open(path,"wb").write(s.encode("utf-8"))
