import { DateTime } from "luxon";
import type { GameProps, GameStatus } from "../../types/sports/sportsTypes";
import type { INBAGame } from "../../types/sports/nbaTypes";
import { mapESPNStatus } from "./sportsUtils";

export const mapStatus = (status: string, date: string): GameStatus => {
  if (status === "In Progress") return "LIVE";
  if (status === "Halftime") return "HALFTIME";
  if (status === "End of Period") return "LIVE";
  if (status === "Final") return "FINAL";

  const gameTime = DateTime.fromISO(date);
  const now = DateTime.now();

  const diffMinutes = gameTime.diff(now, "minutes").minutes;

  if (diffMinutes <= 30 && diffMinutes > 0) {
    return "PRE";
  }

  return "FUT";
};

export const mapNBAToGameProps = (game: INBAGame): GameProps => {
  const title = `${game.homeTeam.name} vs ${
    game.awayTeam.name
  }`;

  return {
    id: game.id,

    title,
    startTime: game.date,

    status: mapESPNStatus(game.status, game.date),

    homeTeam: {
      name: game.homeTeam.name,
      logo: game.homeTeam.logo,
      score: game.homeTeam.score, 
      abbrev: game.homeTeam.abbreviation,
      league: "NBA"
    },

    awayTeam: {
      name: game.awayTeam.name,
      logo: game.awayTeam.logo,
      score: game.awayTeam.score,
      abbrev: game.awayTeam.abbreviation,
      league: "NBA"
    },

    periodNumber: game.period?.type === "OT"
      ? "OT"
      : game.period?.current
      ? `Q${game.period.current}`
      : undefined,

    clock: game.clock ?? undefined,
    gameLink: game.gameLink ?? "",
    leagueName: "NBA",
  };
};