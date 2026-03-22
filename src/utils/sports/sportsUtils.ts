import type { GameProps } from "../../components/ui/GameCard/GameCard";
import type { QuickFilter } from "../../pages/Sports/Sports";
import type { TStreamProvider } from "../../types/sports/sportsTypes"

export const getStreamURL = (streamType: TStreamProvider, channel: string) => {
    switch(streamType) {
        case "sharkstreams": 
            return `https://sharkstreams.net/player.php?channel=${channel}`
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
      statusFilters.some(f => game.status === f.value);


    // ✅ FINAL RESULT
    return matchesSearch && matchesStatus;
  });
};