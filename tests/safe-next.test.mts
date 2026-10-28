import { safeNext } from "../src/lib/safe-next.ts";
const o = "https://app.example";
const cases: [string|null, string][] = [["/guioes","/guioes"],["/equipa?x=1#a","/equipa?x=1#a"],["//evil.com","/"],["/\t/evil.com","/"],["/\n/evil.com","/"],["/\\evil.com","/"],["https://evil.com","/"],["javascript:alert(1)","/"],[null,"/"],["/%2F%2Fevil.com","/%2F%2Fevil.com"]];
let bad = 0; for (const [i, e] of cases) { const g = safeNext(i, o); if (g !== e) { bad++; console.log("FAIL", JSON.stringify(i), g); } }
console.log(`safeNext ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
