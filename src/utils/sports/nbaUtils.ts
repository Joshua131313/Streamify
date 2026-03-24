import { DateTime } from "luxon";
import type { GameProps, GameStatus, TStreamProvider } from "../../types/sports/sportsTypes";
import type { INBAGame } from "../../types/sports/nbaTypes";
import { nbaTeamsMap } from "../../data/sports/nbaData";

export const mapStatus = (status: string, date: string): GameStatus => {
  if (status === "In Progress") return "LIVE";
  if (status === "Halftime") return "HALFTIME";
  if (status === "End of Period") return "LIVE";
  if (status === "Final") return "FINAL";

  // Scheduled → decide PRE or FUT
  const gameTime = DateTime.fromISO(date);
  const now = DateTime.now();

  const diffMinutes = gameTime.diff(now, "minutes").minutes;

  if (diffMinutes <= 30 && diffMinutes > 0) {
    return "PRE";
  }

  return "FUT";
};

export const mapNBAToGameProps = (game: INBAGame): GameProps => {
  // safer title (use abbreviations if available)
  const title = `${game.homeTeam.name} vs ${
    game.awayTeam.name
  }`;

  return {
    id: game.id,

    title,
    startTime: game.startTimeUTC ?? game.date,

    // 🔥 use backend status (don’t recompute)
    status: mapStatus(game.status, game.date),

    homeTeam: {
      name: game.homeTeam.name,
      logo: game.homeTeam.logo,
      score: game.homeTeam.score, // ✅ include score
    },

    awayTeam: {
      name: game.awayTeam.name,
      logo: game.awayTeam.logo,
      score: game.awayTeam.score, // ✅ include score
    },

    // 🔥 real live info
    periodNumber: game.period?.type === "OT"
      ? "OT"
      : game.period?.current
      ? `Q${game.period.current}`
      : undefined,

    clock: game.clock ?? undefined,
    gameLink: game.gameLink ?? "",
    // 🎥 stream
    streamProvider: (game.streamProvider as TStreamProvider) ?? "trendy47",
    channel: nbaTeamsMap[game.awayTeam.abbreviation as keyof typeof nbaTeamsMap]?.id + "-vs-" + nbaTeamsMap[game.homeTeam.abbreviation as keyof typeof nbaTeamsMap]?.id,

    sportName: "Basketball",
  };
};