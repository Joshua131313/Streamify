import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import test from 'node:test';
import ts from 'typescript';

const source = readFileSync(new URL('../src/data/mediaServers.ts', import.meta.url), 'utf8');
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext } });
const { mediaServers, getMediaServer, buildMediaEmbedUrl } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);

test('every server supports movies and explicit TV episodes', () => {
    assert.equal(new Set(mediaServers.map(server => server.id)).size, 15);
    for (const server of mediaServers) {
        for (const type of ['movie', 'tv']) {
            const url = buildMediaEmbedUrl(server.id, type, 1148365, 2, 3);
            assert.equal(new URL(url).protocol, 'https:');
            assert.ok(url.includes('1148365'));
            assert.ok(!/[{}]/.test(url));
        }
    }
});
test('preserves provider-specific episode formats', () => {
    assert.equal(buildMediaEmbedUrl('streamex', 'tv', 123542, 1, 2), 'https://play.xpass.top/e/tv/123542/1/2');
    assert.equal(buildMediaEmbedUrl('stellar', 'tv', 123542, 2, 3), 'https://stellar.rip/en/watch/embed/tv/123542-2-3');
    assert.equal(buildMediaEmbedUrl('french', 'tv', 123542, 2, 3), 'https://frembed.buzz/api/serie.php?id=123542&sa=2&epi=3');
});
test('invalid server and episode parameters fall back safely', () => {
    assert.equal(getMediaServer('vidking').id, 'streamex');
    assert.equal(buildMediaEmbedUrl(null, 'tv', 123542, -1, NaN), 'https://play.xpass.top/e/tv/123542/1/1');
});
