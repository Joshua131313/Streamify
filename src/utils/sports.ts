import  {type IGames, type TStreamProvider } from "../types/sports";
import { DateTime } from "luxon";

export const getGameStatus = (date: string) => {
  const gameTime = DateTime.fromISO(date, { zone: "America/Toronto" });
  const now = DateTime.now().setZone("America/Toronto");

  return gameTime.toMillis() <= now.toMillis() ? "live" : "not_started";
};


export const filterGames = (games: IGames, search: string): IGames => {
    return games.filter(game => {
        const searchNormalized = search.toLocaleLowerCase().trim();
        const awayTeamNormalized = game.awayTeam.name.toLocaleLowerCase();
        const homeTeamNormalized = game.homeTeam.name.toLocaleLowerCase();
        const gameNormalized = game.game.toLocaleLowerCase();
        if (
            awayTeamNormalized.includes(searchNormalized) ||
            homeTeamNormalized.includes(searchNormalized) ||
            gameNormalized.includes(searchNormalized)
        ) {
            return game;
        }
    })
}

export const streamTypeToStreamBaseURL = (streamType: TStreamProvider) => {
    switch(streamType) {
        case "sharkstreams": 
            return "https://sharkstreams.net/player.php?"
    }
}
export const getStreamURL = (streamType: TStreamProvider, channel: number) => {
    return streamTypeToStreamBaseURL(streamType) + `&channel=${channel}`
} 