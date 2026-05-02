import { DateTime } from "luxon";
import { mlbStreams, mlbTeamsMap } from "../../data/sports/mlbData";
import { nbaStreams, nbaTeamsMap } from "../../data/sports/nbaData";
import { nhlStreams, nhlTeamsMap } from "../../data/sports/nhlData";
import { channelStreams } from "../../data/sports/sportsData";
import type { GameProps, GameStatus, Leagues, TeamAbbrevs, TeamInfo, TStreamProvider } from "../../types/sports/sportsTypes"
import type { SportFilter } from "../../context/SportsContext";


const sportsStreamsMap = Object.fromEntries(
    channelStreams.map(s => [s.provider, s])
);


export const getDefaultStreamProvider = (league: Leagues) => {
    const defaultSportStream = getSportStream(league)[0];
    return defaultSportStream.provider;
}


export const extractStreamInfoFromURL = (url: string) => {
    const params = new URLSearchParams(url);
    const leagueName = params.get("league") as Leagues;
    const awayAbbrev = params.get("away") as TeamAbbrevs;
    const homeAbbrev = params.get("home") as TeamAbbrevs;
    const provider = params.get("provider") as TStreamProvider;
    return {
        leagueName,
        awayAbbrev,
        homeAbbrev,
        provider
    }
}

export const getTeamLogo = (league: Leagues, abbrev: TeamAbbrevs) => {
    const lowerCaseLeague = league.toLowerCase();
    const lowerCaseAbbrev = abbrev.toLowerCase();
    return `https://a.espncdn.com/i/teamlogos/${lowerCaseLeague}/500/scoreboard/${lowerCaseAbbrev}.png`
}


export const getLeagueFromTeam = (abbrev: string): Leagues => {
    if (abbrev in nbaTeamsMap) return "NBA";
    if (abbrev in nhlTeamsMap) return "NHL";
    if (abbrev in mlbTeamsMap) return "MLB";
    return "NBA";
};

export const getTeamsMapFromLeague = (league: Leagues): Record<string, TeamInfo> => {
    switch (league) {
        case "MLB":
            return mlbTeamsMap;
        case "NBA":
            return nbaTeamsMap;
        case "NHL":
            return nhlTeamsMap;
        default:
            throw new Error("league does not have a teams map")
    }
}

export const mapESPNStatus = (
    status: string,
    date: string,
    state?: string
): GameStatus => {
    const normalized = status.toLowerCase();

    if (state === "in") return "LIVE";
    if (state === "post") return "FINAL";


    if (normalized.includes("progress")) return "LIVE";
    if (normalized.includes("halftime")) return "HALFTIME";
    if (normalized.includes("end of")) return "LIVE";
    if (normalized.includes("final")) return "FINAL";


    const gameTime = DateTime.fromISO(date);
    const now = DateTime.now();

    const diffMinutes = gameTime.diff(now, "minutes").minutes;

    if (diffMinutes <= 30 && diffMinutes > 0) {
        return "PRE";
    }

    return "FUT";
};

export const formatChannel = (channel: string, provider: string) => {
    const num = Number(channel);
    if (isNaN(num)) return channel;

    if (provider === "shd247") {
        return String(num).padStart(3, "0");
    }

    return String(num);
};

export const getSportStream = (league: Leagues) => {
    switch (league) {
        case "NBA":
            return nbaStreams;
        case "NHL":
            return nhlStreams;
        case "MLB":
            return mlbStreams;
        default:
            return [];
    }
}

export const getStreamURL = (streamType: TStreamProvider, channel: string) => {
    switch (streamType) {
        // nba streams
        case "trendy47":
            return `https://v2.trendy47.com/event/ppv-${channel}`
        // nhl streams
        case "embedsports-away":
            return `https://embedsports.top/embed/admin/ppv-${channel}/1`
        // tv channel streams
        default: {
            const stream = sportsStreamsMap[streamType];
            if (!stream) return "";
            return `${stream.baseUrl}${channel}${stream.extension || ""}`
        }
    }
}
export const getPriority = (status: GameStatus): number => {
    switch (status) {
        case "LIVE": return 0;
        case "HALFTIME": return 1;
        case "PRE": return 2;
        case "FUT": return 3;
        case "FINAL": return 4;
        default: return 5;
    }
};
const matchesSearch = (game: GameProps, search: string): boolean => {
    const s = search.toLowerCase().trim();
    if (!s) return true;

    return (
        game.title.toLowerCase().includes(s) ||
        game.homeTeam.name.toLowerCase().includes(s) ||
        game.awayTeam.name.toLowerCase().includes(s)
    );
};

const matchesStatus = (game: GameProps, filters: SportFilter[]): boolean => {
    const statusFilters = filters.filter(f => f.type === "status");

    if (statusFilters.length === 0) return true;

    return statusFilters.some(f => {
        if (f.value === "LIVE") {
            return game.status === "LIVE" || game.status === "HALFTIME";
        }
        return game.status === f.value;
    });
};

const matchesLeague = (game: GameProps, filters: SportFilter[]): boolean => {
    const leagueFilters = filters.filter(f => f.type === "league");

    if (leagueFilters.length === 0) return true;

    return leagueFilters.some(f => f.value === game.leagueName);
};
const isLiveGame = (game: GameProps) =>
    game.status === "LIVE" || game.status === "HALFTIME";

const getGameProgress = (game: GameProps): number => {
    const period = parseInt(game.periodNumber || "1", 10);

    // Convert clock → seconds remaining
    const parseClock = () => {
        if (!game.clock) return 0;

        // MLB sometimes has "top"/"bot" instead of time
        if (isNaN(Number(game.clock))) {
            return 0;
        }

        const match = game.clock.match(/(\d{1,2}):(\d{2})/);
        if (!match) return 0;

        const mins = parseInt(match[1], 10);
        const secs = parseInt(match[2], 10);
        return mins * 60 + secs;
    };

    const remaining = parseClock();

    /* ---------- MLB ---------- */
    if (game.leagueName === "MLB") {
        const inning = period;

        let half = 0; // 0 = top, 0.5 = bottom
        const text = (game.clock || "").toLowerCase();

        if (text.includes("bot")) half = 0.5;

        return (inning - 1 + half) / 9;
    }

    /* ---------- NBA ---------- */
    if (game.leagueName === "NBA") {
        const quarter = period;
        const totalSeconds = 4 * 720;
        const elapsed =
            (quarter - 1) * 720 + (720 - remaining);

        return elapsed / totalSeconds;
    }

    /* ---------- NHL ---------- */
    if (game.leagueName === "NHL") {
        const periodNum = period;
        const totalSeconds = 3 * 1200;
        const elapsed =
            (periodNum - 1) * 1200 + (1200 - remaining);

        return elapsed / totalSeconds;
    }

    return 0;
};
export const filterGames = (
    games: GameProps[],
    search: string,
    filters: SportFilter[]
): GameProps[] => {

    // 1. FILTER
    const filtered = games.filter(game =>
        matchesSearch(game, search) &&
        matchesStatus(game, filters) &&
        matchesLeague(game, filters)
    );

    // 2. SPLIT
    const liveGames: GameProps[] = [];
    const otherGames: GameProps[] = [];

    filtered.forEach(game => {
        if (isLiveGame(game)) {
            liveGames.push(game);
        } else {
            otherGames.push(game);
        }
    });

    // 3. SORT LIVE BY PROGRESS (MOST ADVANCED FIRST)
    liveGames.sort((a, b) => getGameProgress(b) - getGameProgress(a));

    // 4. RETURN
    return [...liveGames, ...otherGames];
};

export const gameIsWatchable = (
    startTime: string,
    gameStatus?: GameStatus
): boolean => {
    const now = Date.now();
    const gameTime = new Date(startTime).getTime();

    const oneHour = 60 * 60 * 1000;

    let status: GameStatus;

    if (!gameStatus) {
        if (now < gameTime - oneHour) {
            status = "FUT";
        } else if (now > gameTime + 3 * oneHour) {
            status = "FINAL";
        } else {
            status = "LIVE";
        }
    } else {
        status = gameStatus;
    }

    if (status === "FUT" && gameTime - now > oneHour) {
        return false;
    }

    if (status === "FINAL" && now - gameTime > 3 * oneHour) {
        return false;
    }

    return true;
};

