import { teamsMap } from "../../data/sports/nhlData";
import type { NHLGame, ScheduleResponse } from "../../types/sports/nhlTypes";
import type { GameProps } from "../../types/sports/sportsTypes";

// export const buildEmbedUrl = (awayId: string, homeId: string) =>
//     `https://embedsports.top/embed/admin/ppv-${awayId}-vs-${homeId}/1`;

// Extract all games from response
export const extractGames = (data: ScheduleResponse): NHLGame[] =>
    data.gameWeek.flatMap(day => day.games);

export const mapNHLToGameProps = (game: NHLGame): GameProps => {
    const mapStatus = (): GameProps["status"] => {
        switch (game.gameState) {
            case "LIVE":
            case "CRIT":
                return "LIVE";
            case "PRE":
                return "PRE";
            case "FUT":
                return "FUT";
            case "OFF":
            case "FINAL":
                return "FINAL";
            default:
                return "FUT";
        }
    };

    const homeTeamname = game.homeTeam.placeName.default + " " + game.homeTeam.commonName.default;
    const awawyTeamName = game.awayTeam.placeName.default + " " + game.awayTeam.commonName.default;

    return {
        id: game.id,
        title: `${homeTeamname} vs ${awawyTeamName}`,

        startTime: game.startTimeUTC,
        status: mapStatus(),

        homeTeam: {
            name: homeTeamname,
            logo: game.homeTeam.logo,
            score: game.homeTeam.score,
            abbrev: game.homeTeam.abbrev
        },

        awayTeam: {
            name: awawyTeamName,
            logo: game.awayTeam.logo,
            score: game.awayTeam.score,
            abbrev: game.awayTeam.abbrev
        },
        gameLink: `https://www.nhl.com${game.gameCenterLink}`,
        period: game.periodDescriptor?.periodType,
        periodNumber: "P" + String(game.periodDescriptor?.number),
        leagueName: "NHL",
    };
};