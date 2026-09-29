"""Extract the NovaUI source that ships in NovaUI.zip into tools/_nova.

The bridge is written against NovaUI's real API, so the integration test has to
run the real library rather than a mock. tools/_nova is generated and ignored by
git - only NovaUI.zip is committed.
"""
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ZIP = os.path.join(os.path.dirname(HERE), "NovaUI.zip")
OUT = os.path.join(HERE, "_nova")


def main():
    if not os.path.isfile(ZIP):
        print("SKIP: NovaUI.zip not found next to the project root")
        return 0
    with zipfile.ZipFile(ZIP) as zf:
        zf.extractall(OUT)
    print("extracted NovaUI -> %s" % OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
