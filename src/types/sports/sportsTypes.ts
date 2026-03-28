import type { mlbTeamsMap } from "../../data/sports/mlbData";
import type { nbaTeamsMap } from "../../data/sports/nbaData";
import type { nhlTeamsMap } from "../../data/sports/nhlData";

export type TStreamProvider = 
    "trendy47" | "topstreams" // nba providers
    | "embedsports" // nhl providers
    | "mlbwebcast" | "embedsports-d" | "pooembed" // mlb providers
    | "rippleplays" | "shd247" | "prostreams" | "streamscenter"; // tv channel providers


export type GameStatus = "LIVE" | "PRE" | "FUT" | "FINAL" | "HALFTIME";
export type Leagues = "NBA" | "NHL" | "MLB";

export type TeamAbbrevs = 
        keyof typeof nbaTeamsMap | 
        keyof typeof nhlTeamsMap | 
        keyof typeof mlbTeamsMap |
        "";

export interface ChannelStream {
    baseUrl: string;
    extension: string;
    defaultChannel: string;
    title: string;
    provider: TStreamProvider;
}

export interface GameTeam {
    name: string;
    abbrev: TeamAbbrevs;
    logo: string;
    score?: number;
}

export interface GameProps {
    id?: string | number;
    title: string;

    homeTeam: GameTeam;
    awayTeam: GameTeam;

    startTime: string;
    status: GameStatus;

    period?: string;
    periodNumber?: string;
    clock?: string;
    gameLink: string;
    leagueName: Leagues;
}


type StreamBuilder = (params: {
    homeTeamAbbrev: TeamAbbrevs;
    awayTeamAbbrev: TeamAbbrevs;
}) => string;

export type SportStream = {
    provider: TStreamProvider;
    buildStreamUrl: StreamBuilder;
    buildChannel: StreamBuilder;
}

export const DefaultGamePropsTeam: GameTeam = {
    name: "",
    abbrev: "",
    logo: "",
    score: undefined
};

export const DefaultGameProps: GameProps = {
    id: undefined,
    title: "",

    homeTeam: DefaultGamePropsTeam,
    awayTeam: DefaultGamePropsTeam,

    startTime: "",
    status: "PRE", 

    period: undefined,
    periodNumber: undefined,
    clock: undefined,
    gameLink: "",
    leagueName: "NBA",
};

