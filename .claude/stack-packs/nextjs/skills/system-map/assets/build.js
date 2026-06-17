#!/usr/bin/env node
/* 汎用: template.html の __DATA__ に combined.json を差し込んで単一HTMLを生成。
 * 使い方: node build.js [template=assets/template.html] [combined=combined.json] [out=system-map.html] */
const fs = require('fs');
const tplPath = process.argv[2] || require('path').join(__dirname, 'template.html');
const dataPath = process.argv[3] || 'combined.json';
const outPath = process.argv[4] || 'system-map.html';
const tpl = fs.readFileSync(tplPath, 'utf8');
let data = fs.readFileSync(dataPath, 'utf8');
data = data.replace(/</g, '\\u003c'); // </script> 早期終了と < を無害化
if (!tpl.includes('__DATA__')) { console.error('ERROR: __DATA__ placeholder not found in template'); process.exit(1); }
fs.writeFileSync(outPath, tpl.replace('__DATA__', data), 'utf8');
console.log('built:', outPath, fs.statSync(outPath).size, 'bytes');
