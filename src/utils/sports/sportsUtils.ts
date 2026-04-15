import { DateTime } from "luxon";
import { mlbStreams, mlbTeamsMap } from "../../data/sports/mlbData";
import { nbaStreams, nbaTeamsMap } from "../../data/sports/nbaData";
import { nhlStreams, nhlTeamsMap } from "../../data/sports/nhlData";
import { channelStreams } from "../../data/sports/sportsData";
import type { GameProps, GameStatus, Leagues, TeamAbbrevs, TStreamProvider } from "../../types/sports/sportsTypes"
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


export const getLeagueFromTeam = (abbrev: string) : Leagues => {
    if (abbrev in nbaTeamsMap) return "NBA";
    if (abbrev in nhlTeamsMap) return "NHL";
    if (abbrev in mlbTeamsMap) return "MLB";
    return "NBA";
};

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
        case "embedsports":
            return `https://embedsports.top/embed/admin/ppv-${channel}/1`
        // tv channel streams
        default: {
            const stream = sportsStreamsMap[streamType];
            if (!stream) return "";
            return `${stream.baseUrl}${channel}${stream.extension || ""}`
        }
    }
}
export const getPriority = (status: string) => {
    switch (status) {
        case "LIVE": return 0;
        case "HALFTIME": return 1;
        case "PRE": return 2;
        case "FUT": return 3;
        case "FINAL": return 4;
        default: return 5;
    }
};

export const filterGames = (
    games: GameProps[],
    search: string,
    filters: SportFilter[]
): GameProps[] => {
    const searchNormalized = search.toLowerCase().trim();

    const statusFilters = filters.filter(f => f.type === "status");
    const leagueFilters = filters.filter(f => f.type === "league");

    const filtered = games.filter(game => {
        const matchesSearch =
            !searchNormalized ||
            game.title.toLowerCase().includes(searchNormalized) ||
            game.homeTeam.name.toLowerCase().includes(searchNormalized) ||
            game.awayTeam.name.toLowerCase().includes(searchNormalized);

        const matchesStatus =
            statusFilters.length === 0 ||
            statusFilters.some(f => {
                if (f.value === "LIVE") {
                    return game.status === "LIVE" || game.status === "HALFTIME";
                }
                return game.status === f.value;
            });

        const matchesLeague =
            leagueFilters.length === 0 ||
            leagueFilters.some(f => f.value === game.leagueName);

        return matchesSearch && matchesStatus && matchesLeague;
    });

    return filtered.sort((a, b) => {
        const priorityDiff = getPriority(a.status) - getPriority(b.status);

        if (priorityDiff !== 0) {
            return priorityDiff;
        }

        const timeA = new Date(a.startTime).getTime();
        const timeB = new Date(b.startTime).getTime();

        const isLiveA = a.status === "LIVE" || a.status === "HALFTIME";

        if (isLiveA) {
            return timeB - timeA;
        }

        return timeA - timeB;
    });
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

