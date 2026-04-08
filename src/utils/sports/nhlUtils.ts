import type { INHLGame } from "../../types/sports/nhlTypes";
import type { GameProps } from "../../types/sports/sportsTypes";
import { mapESPNStatus } from "./sportsUtils";

export const mapNHLToGameProps = (game: INHLGame): GameProps => {
  return {
    id: game.id,

    title: `${game.homeTeam.name} vs ${game.awayTeam.name}`,

    startTime: game.date,

    status: mapESPNStatus(game.status, game.date, game.state),

    homeTeam: {
      name: game.homeTeam.name,
      logo: game.homeTeam.logo,
      score: game.homeTeam.score,
      abbrev: game.homeTeam.abbreviation,
    },

    awayTeam: {
      name: game.awayTeam.name,
      logo: game.awayTeam.logo,
      score: game.awayTeam.score,
      abbrev: game.awayTeam.abbreviation,
    },

    gameLink: game.gameLink ?? "",

    period: game.period.type,
    periodNumber: `P${game.period.current}`,
    clock: game.clock,
    leagueName: "NHL",
  };
};