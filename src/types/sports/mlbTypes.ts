import type { mlbTeamsMap } from "../../data/sports/mlbData";

export type MLBGameState =
    | "pre"
    | "in"
    | "post";

export type MLBInningHalf =
    | "top"
    | "bottom"
    | "mid"
    | "end"
    | null;

export interface MLBTeam {

    id: string;

    name: string;

    abbreviation: keyof typeof mlbTeamsMap;

    logo: string;

    score: number;

    hits?: number | null;

    errors?: number | null;

    record?: string;

    records?: MLBTeamRecord[];
}

export interface MLBTeamRecord {

    name: string;

    abbreviation: string;

    type: string;

    summary: string;
}


export interface MLBPeriod {

    current: number;

    type?: string | null;

    inningHalf: MLBInningHalf;

    isHalftime: boolean;
}


export interface MLBBroadcast {

    market?: string;

    network: string;
}

export interface MLBBases {

    first: boolean;

    second: boolean;

    third: boolean;
}


export interface MLBStatValue {

    value: number | null;

    displayValue: string | null;
}

export interface MLBPlayerStats {

    atBats?: MLBStatValue | null;

    hits?: MLBStatValue | null;

    runs?: MLBStatValue | null;

    rbis?: MLBStatValue | null;

    pitchesSeen?: MLBStatValue | null;


    pitches?: MLBStatValue | null;

    strikeouts?: MLBStatValue | null;

    walks?: MLBStatValue | null;

    earnedRuns?: MLBStatValue | null;

    hitsAllowed?: MLBStatValue | null;
}

export interface MLBPlayer {

    id: string | null;

    name: string | null;

    shortName: string | null;

    jersey: string | null;

    headshot: string | null;

    position: string | null;

    teamId: string | null;

    summary: string | null;

    stats?: MLBPlayerStats | null;
}


export interface MLBRunner {

    base: 1 | 2 | 3;

    id: string | null;

    name: string | null;

    shortName: string | null;

    jersey: string | null;

    headshot: string | null;

    position: string | null;
}


export interface MLBProbabilityData {

    score1Plus: string | null;

    score1PlusPercent: number | null;

    score2Plus: string | null;

    score2PlusPercent: number | null;
}
export interface MLBLastPlay {

    id: string | null;

    text: string | null;

    type: string | null;


    shortType: string | null;

    playType: string | null;

    scoreValue: number | null;

    teamId: string | null;
}

export interface MLBLiveGameData {

    isActiveAtBat: boolean;

    balls: number | null;

    strikes: number | null;

    outs: number | null;

    pitchCount: number | null;

    atBatPitchCount?: number | null;

    batter: MLBPlayer | null;

    pitcher: MLBPlayer | null;

    bases: MLBBases;

    runners: MLBRunner[];

    probabilities: MLBProbabilityData;

    lastPlay: MLBLastPlay | null;

    basesLoaded: boolean;

    runnersInScoringPosition: boolean;

    linescore: MLBLineScore[];
}


export interface IMLBGame {

    id: string;

    uid?: string;

    name?: string;

    shortName?: string;

    date: string;

    venue?: string | null;

    status: string;

    state?: MLBGameState;

    completed?: boolean;

    clock?: string | null;

    period: MLBPeriod;

    inningDisplay?: string | null;


    live?: MLBLiveGameData;

    homeTeam: MLBTeam;

    awayTeam: MLBTeam;
    broadcasts?: string[];

    gameLink?: string | null;
}

export interface MLBLineScore {

    inning: number;

    home: number | null;

    away: number | null;
}