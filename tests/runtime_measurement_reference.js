const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'ledger-measurement-'));
const hash = raw => 'sha256:' + crypto.createHash('sha256').update(raw).digest('hex');
const marker = 'PRIVATE_sk-123_prompt_document';
function cli(args, success = true) {
    const r = spawnSync(process.env.KUJO || 'kujo', ['run',path.join(root,'runledger.kujo'),'--',...args,'--ledger',path.join(temp,'ledger')], {cwd:root, encoding:'utf8', timeout:30000});
    assert.ifError(r.error);
    if (success) assert.equal(r.status,0,r.stdout+r.stderr); else assert.notEqual(r.status,0);
    assert(!(r.stdout+r.stderr).includes(marker));
    return r.stdout;
}
try {
    cli(['start','--provider','unknown','--model','unknown','--task','measurement-reference','--repo',temp]);
    const id = fs.readdirSync(path.join(temp,'ledger/runs'))[0].replace(/\.json$/,'');
    const raw = JSON.stringify({schema:'kujo.runtime-measurements/v1',extension:marker});
    fs.writeFileSync(path.join(temp,'report.json'),raw);
    const attach = (file,artifact,ok) => cli(['runtime-measurement',id,'--root',temp,'--file',file,'--artifact',artifact],ok);
    attach('report.json',hash(raw),true); attach('report.json',hash(raw),true);
    const before = cli(['show',id,'--json']);
    const receipt = JSON.parse(before);
    assert.equal(receipt.notes.length,1);
    assert.equal(JSON.parse(receipt.notes[0].text).artifact,hash(raw));
    assert.equal(receipt.status,'in_progress');
    assert(Object.values(receipt.usage).every(x=>x===null));
    assert.equal(receipt.cost.total_cost,null);
    attach('report.json','sha256:'+'0'.repeat(64),false);
    attach('report.json','https://user:password@example.invalid',false);
    fs.writeFileSync(path.join(temp,'report.json'),raw+' ');
    attach('report.json',hash(raw),false);
    for (const bad of ['{', JSON.stringify({schema:'kujo.runtime-measurements/v2'}), ' '.repeat(8193)]) {
        fs.writeFileSync(path.join(temp,'bad.json'),bad); attach('bad.json',hash(bad),false);
    }
    fs.symlinkSync(path.join(temp,'report.json'),path.join(temp,'link.json'));
    attach('link.json',hash(raw+' '),false);
    attach('../report.json',hash(raw),false);
    attach(path.join(temp,'report.json'),hash(raw+' '),false);
    assert.equal(cli(['show',id,'--json']),before,'rejection changed receipt');
    console.log('runtime_measurement_reference: PASS');
} finally { fs.rmSync(temp,{recursive:true,force:true}); }
