import type { INHLGame } from "../../types/sports/nhlTypes";
import type { GameProps } from "../../types/sports/sportsTypes";

export const mapNHLToGameProps = (game: INHLGame): GameProps => {
  const mapStatus = (): GameProps["status"] => {
    switch (game.state) {
      case "in":
        return "LIVE";
      case "pre":
        return "PRE";
      case "post":
        return "FINAL";
      default:
        return "FUT";
    }
  };

  return {
    id: game.id,

    title: `${game.homeTeam.name} vs ${game.awayTeam.name}`,

    startTime: game.date,

    status: mapStatus(),

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

    // 🔥 clean period handling
    period: game.period.type,
    periodNumber: `P${game.period.current}`,
    clock: game.clock,
    leagueName: "NHL",
  };
};