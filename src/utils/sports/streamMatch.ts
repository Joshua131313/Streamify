export interface StreamMatch {
    id: string;
    title: string;
    category: string;
    date: number;
    teams?: { home?: { name: string }; away?: { name: string } };
    sources: { source: string; id: string }[];
}

const normalize = (name: string) => name.toLowerCase()
    .replace(/\b(st\.? louis)\b/g, "saint louis")
    .replace(/\bla\b/g, "los angeles")
    .replace(/[^a-z0-9]/g, "");

export function findStreamMatch(matches: StreamMatch[], category: string, home: string, away: string) {
    if (!home || !away) return undefined;
    const homeName = normalize(home);
    const awayName = normalize(away);
    // Require both full team names: city-only matches can select the wrong league.
    return matches.filter(match => {
        if (match.category !== category || !match.sources?.length) return false;
        if (match.date !== 1 && Math.abs(match.date - Date.now()) > 18 * 60 * 60 * 1000) return false;
        const title = normalize(match.title);
        const teams = [match.teams?.home?.name, match.teams?.away?.name].map(name => normalize(name ?? ""));
        return (teams.includes(homeName) && teams.includes(awayName)) ||
            (title.includes(homeName) && title.includes(awayName));
    }).sort((a, b) => Math.abs(a.date - Date.now()) - Math.abs(b.date - Date.now()))[0];
}
