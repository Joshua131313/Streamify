import { DateTime } from "luxon";
import type { IMLBGame } from "../../types/sports/mlbTypes";
import type { GameProps, GameStatus } from "../../types/sports/sportsTypes";
import { mapESPNStatus } from "./sportsUtils";

export const mapMLBStatus = (
  status: string,
  date: string,
  state?: string
): GameStatus => {
  if (state === "in") return "LIVE";
  if (state === "post") return "FINAL";

  if (status === "In Progress") return "LIVE";
  if (status === "Final") return "FINAL";

  const gameTime = DateTime.fromISO(date);
  const now = DateTime.now();

  const diffMinutes = gameTime.diff(now, "minutes").minutes;

  if (diffMinutes <= 30 && diffMinutes > 0) {
    return "PRE";
  }

  return "FUT";
};

export const mapMLBToGameProps = (game: IMLBGame): GameProps => {
  const title = `${game.homeTeam.name} vs ${game.awayTeam.name}`;
  return {
    id: game.id,

    title,
    startTime: game.date,

    status: mapESPNStatus(game.status, game.date, game.state),

    homeTeam: {
      name: game.homeTeam.name,
      logo: game.homeTeam.logo,
      score: game.homeTeam.score,
      abbrev: game.homeTeam.abbreviation,
      league: "MLB"
    },

    awayTeam: {
      name: game.awayTeam.name,
      logo: game.awayTeam.logo,
      score: game.awayTeam.score,
      abbrev: game.awayTeam.abbreviation,
      league: "MLB"
    },

    periodNumber: game.period.current.toString(),

    clock: game.period.inningHalf?.toString(),

    gameLink: game.gameLink ?? "",

    leagueName: "MLB"
  };
};