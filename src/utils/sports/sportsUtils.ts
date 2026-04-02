import { DateTime } from "luxon";
import { mlbStreams } from "../../data/sports/mlbData";
import { nbaStreams } from "../../data/sports/nbaData";
import { nhlStreams } from "../../data/sports/nhlData";
import { channelStreams } from "../../data/sports/sportsData";
import type { QuickFilter } from "../../pages/Sports/Sports";
import type { GameProps, GameStatus, Leagues, TeamAbbrevs, TStreamProvider } from "../../types/sports/sportsTypes"


const sportsStreamsMap = Object.fromEntries(
    channelStreams.map(s => [s.provider, s])
);

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

export const mapESPNStatus = (
    status: string,
    date: string,
    state?: string
): GameStatus => {
    const normalized = status.toLowerCase();

    // =====================
    // 🔥 PRIORITY: STATE (most reliable when correct)
    // =====================
    if (state === "in") return "LIVE";
    if (state === "post") return "FINAL";

    // =====================
    // 🔥 TEXT-BASED (ESPN description)
    // =====================
    if (normalized.includes("progress")) return "LIVE";
    if (normalized.includes("halftime")) return "HALFTIME";
    if (normalized.includes("end of")) return "LIVE";
    if (normalized.includes("final")) return "FINAL";

    // =====================
    // 🔥 TIME-BASED (PRE vs FUT)
    // =====================
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

export const filterGames = (
    games: GameProps[],
    search: string,
    filters: QuickFilter[]
): GameProps[] => {
    const searchNormalized = search.toLowerCase().trim();

    if(filters.length == 0) return games;

    return games.filter(game => {
        // 🔍 SEARCH
        const matchesSearch =
            !searchNormalized ||
            game.title.toLowerCase().includes(searchNormalized) ||
            game.homeTeam.name.toLowerCase().includes(searchNormalized) ||
            game.awayTeam.name.toLowerCase().includes(searchNormalized);

        // 🎯 STATUS FILTER
        const statusFilters = filters.filter(f => f.type === "status");
        const matchesStatus =
            statusFilters.length === 0 ||
            statusFilters.some(f => {
                if (f.value === "LIVE") {
                    return game.status === "LIVE" || game.status === "HALFTIME"
                }
                return game.status === f.value
            });


        // ✅ FINAL RESULT
        return matchesSearch && matchesStatus;
    });
};


export const gameIsWatchable = (startTime: string, gameStatus: GameStatus): boolean => {
    const now = Date.now();
    const gameTime = new Date(startTime).getTime();

    const oneHour = 60 * 60 * 1000;

    return !(gameStatus === "FUT" && gameTime - now > oneHour) && !(gameStatus === "FINAL" && now - gameTime > oneHour);
}