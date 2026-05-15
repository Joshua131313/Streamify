import type { nbaTeamsMap } from "../../data/sports/nbaData";

export type NBAGameState =
    | "pre"
    | "in"
    | "post";

export type NBAGameStatus =
    | "SCHEDULED"
    | "PRE"
    | "LIVE"
    | "HALFTIME"
    | "FINAL";

export interface NBATeam {

    id: string;

    name: string;

    abbreviation: keyof typeof nbaTeamsMap;

    logo: string;

    score: number;

    record?: string | null;

    fouls?: number | null;

    timeouts?: number | null;

    wins?: number | null;

    losses?: number | null;
}

export interface NBAPeriod {

    current: number;

    type: "REG" | "OT";

    isHalftime: boolean;
}

export interface NBAPlayer {

    id: string | null;

    name: string | null;

    shortName: string | null;

    jersey: string | null;

    position: string | null;

    headshot: string | null;

    summary?: string | null;
}

export interface NBALastPlay {

    id: string | null;

    text: string | null;

    type: string | null;

    shortType: string | null;

    teamId: string | null;
}

export interface NBAPeriodScore {

    period: number;

    home: number | null;

    away: number | null;
}

export interface NBABroadcast {

    market?: string;

    network: string;
}

export interface NBALiveGameData {

    homeFouls: number | null;

    awayFouls: number | null;

    homeTimeouts: number | null;

    awayTimeouts: number | null;

    possessionTeamId: string | null;

    player: NBAPlayer | null;

    lastPlay: NBALastPlay | null;

    periodScores: NBAPeriodScore[];
}

export interface INBAGame {

    id: string;

    date: string;

    venue?: {
        name: string;
        city?: string;
        state?: string;
    };

    status: string;

    state: NBAGameState;

    clock?: string;

    period?: NBAPeriod;

    live?: NBALiveGameData;

    homeTeam: NBATeam;

    awayTeam: NBATeam;

    broadcasts?: string[];

    gameLink?: string | null;
}