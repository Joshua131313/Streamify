import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import test from 'node:test';
import ts from 'typescript';

const source = readFileSync(new URL('../src/utils/sports/streamMatch.ts', import.meta.url), 'utf8');
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext } });
const { findStreamMatch } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
const match = (overrides = {}) => ({ id: 'game', title: 'Boston Celtics vs Los Angeles Lakers', category: 'basketball', date: Date.now(), sources: [{ source: 'hotel', id: 'provider-event-id' }], ...overrides });

test('matches both teams regardless of home/away order and LA spelling', () => {
    const game = match({ teams: { home: { name: 'Boston Celtics' }, away: { name: 'LA Lakers' } } });
    assert.equal(findStreamMatch([game], 'basketball', 'Los Angeles Lakers', 'Boston Celtics'), game);
});
test('rejects wrong sports, city-only names, stale events and missing sources', () => {
    for (const game of [match({ category: 'baseball' }), match({ title: 'Boston Bruins vs Los Angeles Kings' }), match({ date: Date.now() - 86400000 }), match({ sources: [] })]) {
        assert.equal(findStreamMatch([game], 'basketball', 'Los Angeles Lakers', 'Boston Celtics'), undefined);
    }
    assert.equal(findStreamMatch([match()], 'basketball', '', 'Boston Celtics'), undefined);
});
test('chooses nearest scheduled matchup and accepts always-live events', () => {
    const near = match();
    assert.equal(findStreamMatch([match({ date: Date.now() + 3600000 }), near], 'basketball', 'Boston Celtics', 'Los Angeles Lakers'), near);
    assert.ok(findStreamMatch([match({ date: 1 })], 'basketball', 'Boston Celtics', 'Los Angeles Lakers'));
});
