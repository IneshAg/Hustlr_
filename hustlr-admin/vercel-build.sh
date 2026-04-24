#!/bin/bash
set -euo pipefail

echo "Building static export with Next.js"
npx next build

if [ ! -d "out" ]; then
	echo "ERROR: Next.js static export directory 'out' was not generated"
	exit 1
fi

echo "Preparing Vercel output directory"
rm -rf build/web
mkdir -p build/web
cp -R out/. build/web/

echo "Build complete"