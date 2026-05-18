import type { INBAGame } from "./nbaTypes";
import type { INHLGame } from "./nhlTypes";
import type { IMLBGame } from "./mlbTypes";
import type { GameProps } from "./sportsTypes";

export type SportsLeague =
    | "NBA"
    | "NHL"
    | "MLB";

export type SportDisplayGame =
    | {
        league: "NBA";
        id: string;
        card: GameProps;
        raw: INBAGame;
    }
    |
    {
        league: "WNBA";
        id: string;
        card: GameProps;
        raw: INBAGame;
    }
    | {
        league: "NHL";
        id: string;
        card: GameProps;
        raw: INHLGame;
    }
    | {
        league: "MLB";
        id: string;
        card: GameProps;
        raw: IMLBGame;
    };