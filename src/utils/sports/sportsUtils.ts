import type { QuickFilter } from "../../pages/Sports/Sports";
import type { GameProps, TStreamProvider } from "../../types/sports/sportsTypes"

export const getStreamURL = (streamType: TStreamProvider, channel: string) => {
    switch (streamType) {
        case "trendy47":
            return `https://v2.trendy47.com/event/ppv-${channel}`
        case "embedsports":
            return `https://embedsports.top/embed/admin/ppv-${channel}/1`
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