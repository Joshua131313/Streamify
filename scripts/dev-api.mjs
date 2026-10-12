import { createServer } from 'node:http';
import nba from '../api/nba/index.js';
import wnba from '../api/wnba/index.js';
import nhl from '../api/nhl/index.js';
import mlb from '../api/mlb/index.js';
import health from '../api/health/index.js';

const handlers = { '/api/nba': nba, '/api/wnba': wnba, '/api/nhl': nhl, '/api/mlb': mlb, '/api/health': health };
const port = Number(process.env.PORT || 3000);

createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.status = code => { res.statusCode = code; return res; };
    res.json = data => {
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify(data));
        return res;
    };
    if (req.method === 'OPTIONS') {
        res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
        res.status(204).end();
        return;
    }
    if (req.method !== 'GET') {
        res.setHeader('Allow', 'GET, OPTIONS');
        res.status(405).json({ error: 'Method not allowed' });
        return;
    }
    const path = new URL(req.url, 'http://localhost').pathname.replace(/\/$/, '');
    const handler = handlers[path];
    if (!handler) {
        res.status(404).json({ error: 'Not found' });
        return;
    }
    try {
        await handler(req, res);
    } catch (error) {
        console.error(error);
        if (!res.headersSent) res.status(500).json({ error: 'Request failed' });
        else res.end();
    }
}).listen(port, '127.0.0.1', () => {
    console.log(`Sports API ready at http://localhost:${port}`);
});
