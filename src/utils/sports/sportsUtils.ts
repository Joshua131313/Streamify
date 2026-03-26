import { nbaStreams } from "../../data/sports/nbaData";
import { nhlStreams } from "../../data/sports/nhlData";
import { channelStreams } from "../../data/sports/sportsData";
import type { QuickFilter } from "../../pages/Sports/Sports";
import type { GameProps, Leagues, TStreamProvider } from "../../types/sports/sportsTypes"


const sportsStreamsMap = Object.fromEntries(
    channelStreams.map(s => [s.provider, s])
);
export const formatChannel = (channel: string, provider: string) => {
    const num = Number(channel);
    if (isNaN(num)) return channel;

    if (provider === "shd247") {
        return String(num).padStart(3, "0");
    }

    return String(num);
};

export const getSportStream = (league : Leagues) => {
    switch (league) {
        case "NBA":
            return nbaStreams;
        case "NHL":
            return nhlStreams;
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