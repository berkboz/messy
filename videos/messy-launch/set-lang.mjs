// Sets the film's language on every frame host in index.html (frames read it with getVariables()).
//   node set-lang.mjs tr   |   node set-lang.mjs en
import { readFileSync, writeFileSync } from "node:fs";
const lang = process.argv[2] === "tr" ? "tr" : "en";
let s = readFileSync("index.html", "utf8");
s = s.replace(/\s*data-variable-values='[^']*'/g, "");
s = s.replace(/(data-composition-src="compositions\/frames\/[^"]+")/g, `$1 data-variable-values='{"lang":"${lang}"}'`);
s = s.replace(/("id":"lang"[^\]]*?"default":")(en|tr)(")/, `$1${lang}$3`);
writeFileSync("index.html", s);
console.log(`index.html set to ${lang}`);
