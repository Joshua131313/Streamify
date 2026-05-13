import type { mlbTeamsMap } from "../../data/sports/mlbData";

/*
|--------------------------------------------------------------------------
| CORE
|--------------------------------------------------------------------------
*/

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

/*
|--------------------------------------------------------------------------
| TEAM
|--------------------------------------------------------------------------
*/

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

/*
|--------------------------------------------------------------------------
| TEAM RECORD
|--------------------------------------------------------------------------
*/

export interface MLBTeamRecord {

    name: string;

    abbreviation: string;

    type: string;

    summary: string;
}

/*
|--------------------------------------------------------------------------
| PERIOD
|--------------------------------------------------------------------------
*/

export interface MLBPeriod {

    current: number;

    type?: string | null;

    inningHalf: MLBInningHalf;

    isHalftime: boolean;
}

/*
|--------------------------------------------------------------------------
| BROADCAST
|--------------------------------------------------------------------------
*/

export interface MLBBroadcast {

    market?: string;

    network: string;
}

/*
|--------------------------------------------------------------------------
| BASES
|--------------------------------------------------------------------------
*/

export interface MLBBases {

    first: boolean;

    second: boolean;

    third: boolean;
}

/*
|--------------------------------------------------------------------------
| STAT VALUE
|--------------------------------------------------------------------------
*/

export interface MLBStatValue {

    value: number | null;

    displayValue: string | null;
}

/*
|--------------------------------------------------------------------------
| PLAYER STATS
|--------------------------------------------------------------------------
*/

export interface MLBPlayerStats {

    /*
    |--------------------------------------------------------------------------
    | Batting
    |--------------------------------------------------------------------------
    */

    atBats?: MLBStatValue | null;

    hits?: MLBStatValue | null;

    runs?: MLBStatValue | null;

    rbis?: MLBStatValue | null;

    pitchesSeen?: MLBStatValue | null;

    /*
    |--------------------------------------------------------------------------
    | Pitching
    |--------------------------------------------------------------------------
    */

    pitches?: MLBStatValue | null;

    strikeouts?: MLBStatValue | null;

    walks?: MLBStatValue | null;

    earnedRuns?: MLBStatValue | null;

    hitsAllowed?: MLBStatValue | null;
}

/*
|--------------------------------------------------------------------------
| PLAYER
|--------------------------------------------------------------------------
*/

export interface MLBPlayer {

    id: string | null;

    name: string | null;

    shortName: string | null;

    jersey: string | null;

    headshot: string | null;

    position: string | null;

    teamId: string | null;

    /*
    |--------------------------------------------------------------------------
    | Examples
    |--------------------------------------------------------------------------
    | Batter:
    | "1-2"
    |
    | Pitcher:
    | "5.1 IP, 2 ER, 6 H, 7 K, 1 BB"
    |--------------------------------------------------------------------------
    */

    summary: string | null;

    stats?: MLBPlayerStats | null;
}

/*
|--------------------------------------------------------------------------
| RUNNER
|--------------------------------------------------------------------------
*/

export interface MLBRunner {

    base: 1 | 2 | 3;

    id: string | null;

    name: string | null;

    shortName: string | null;

    jersey: string | null;

    headshot: string | null;

    position: string | null;
}

/*
|--------------------------------------------------------------------------
| PROBABILITIES
|--------------------------------------------------------------------------
*/

export interface MLBProbabilityData {

    /*
    |--------------------------------------------------------------------------
    | Example:
    | "Chance of scoring 1+ runs this inning..."
    |--------------------------------------------------------------------------
    */

    score1Plus: string | null;

    score1PlusPercent: number | null;

    score2Plus: string | null;

    score2PlusPercent: number | null;
}

/*
|--------------------------------------------------------------------------
| LAST PLAY
|--------------------------------------------------------------------------
*/

export interface MLBLastPlay {

    id: string | null;

    /*
    |--------------------------------------------------------------------------
    | Example:
    | "Pitch 5 : Strike 2 Foul"
    |--------------------------------------------------------------------------
    */

    text: string | null;

    /*
    |--------------------------------------------------------------------------
    | Example:
    | "Foul Ball"
    |--------------------------------------------------------------------------
    */

    type: string | null;

    /*
    |--------------------------------------------------------------------------
    | Example:
    | "F"
    |--------------------------------------------------------------------------
    */

    shortType: string | null;

    /*
    |--------------------------------------------------------------------------
    | Example:
    | "foul-ball"
    |--------------------------------------------------------------------------
    */

    playType: string | null;

    scoreValue: number | null;

    teamId: string | null;
}

/*
|--------------------------------------------------------------------------
| LIVE GAME
|--------------------------------------------------------------------------
*/

export interface MLBLiveGameData {

    isActiveAtBat: boolean;

    balls: number | null;

    strikes: number | null;

    outs: number | null;

    /*
    |--------------------------------------------------------------------------
    | Total pitcher pitches
    |--------------------------------------------------------------------------
    */

    pitchCount: number | null;

    /*
    |--------------------------------------------------------------------------
    | Current at-bat pitch number
    |--------------------------------------------------------------------------
    */

    atBatPitchCount?: number | null;

    batter: MLBPlayer | null;

    pitcher: MLBPlayer | null;

    bases: MLBBases;

    runners: MLBRunner[];

    probabilities: MLBProbabilityData;

    lastPlay: MLBLastPlay | null;

    basesLoaded: boolean;

    runnersInScoringPosition: boolean;
}

/*
|--------------------------------------------------------------------------
| ROOT GAME
|--------------------------------------------------------------------------
*/

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

    /*
    |--------------------------------------------------------------------------
    | LIVE
    |--------------------------------------------------------------------------
    */

    live?: MLBLiveGameData;

    /*
    |--------------------------------------------------------------------------
    | TEAMS
    |--------------------------------------------------------------------------
    */

    homeTeam: MLBTeam;

    awayTeam: MLBTeam;

    /*
    |--------------------------------------------------------------------------
    | BROADCASTS
    |--------------------------------------------------------------------------
    */

    broadcasts?: string[];

    /*
    |--------------------------------------------------------------------------
    | LINKS
    |--------------------------------------------------------------------------
    */

    gameLink?: string | null;
}