import type { nhlTeamsMap } from "../../data/sports/nhlData";

export type NHLGameState =
    | "pre"
    | "in"
    | "post";

export type NHLPeriodType =
    | "REG"
    | "OT"
    | "SO";

export interface NHLPeriod {

    current: number;

    type: NHLPeriodType;

    isHalftime: boolean;
}

export interface NHLTeam {

    id: string;

    name: string;

    abbreviation: keyof typeof nhlTeamsMap;

    logo: string;

    score: number;

    shots?: number | null;

    record?: string | null;
}

export interface NHLPeriodScore {

    period: number;

    home: number | null;

    away: number | null;
}

export interface NHLPlayer {

    id: string | null;

    name: string | null;

    shortName: string | null;

    jersey: string | null;

    position: string | null;

    headshot: string | null;

    summary?: string | null;
}

export interface NHLLastPlay {

    id: string | null;

    text: string | null;

    type: string | null;

    shortType: string | null;

    teamId: string | null;
}

export interface NHLPowerPlay {

    strength: string | null;

    advantageTeamId: string | null;

    clock: string | null;

    display: string | null;

    homeSkaters: number | null;

    awaySkaters: number | null;

    isPowerPlay: boolean;

    isEvenStrength: boolean;

    isEmptyNet: boolean;
}

export interface NHLLiveGameData {

    homeShots: number | null;

    awayShots: number | null;

    powerPlay: NHLPowerPlay | null;

    goalie: NHLPlayer | null;

    skater: NHLPlayer | null;

    lastPlay: NHLLastPlay | null;

    periodScores: NHLPeriodScore[];
}

export interface INHLGame {

    id: string;

    date: string;

    status: string;

    state: NHLGameState;

    clock?: string;

    period: NHLPeriod;

    live?: NHLLiveGameData;

    homeTeam: NHLTeam;

    awayTeam: NHLTeam;

    venue?: string | null;

    broadcasts?: string[];

    gameLink?: string | null;
}