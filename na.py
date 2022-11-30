#!/usr/bin/env python3

# Normalize a YAML true/false/yes/no to enable or disable an argument.

import sys
import yaml


def main():

    if len(sys.argv) != 3:
        sys.exit(f"Expected 2 arguments, got: {sys.argv[1:]}")

    y = yaml.safe_load(f"value: {sys.argv[1]}")
    if y["value"]:
        sys.stdout.write(sys.argv[2])


if __name__ == "__main__":
    main()
