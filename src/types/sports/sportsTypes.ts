export type TStreamProvider = 
    "trendy47" | "topstreams" // nba providers
    | "embedsports" // nhl providers
    | "rippleplays" | "shd247" | "prostreams" | "streamscenter"; // tv channel providers


export type GameStatus = "LIVE" | "PRE" | "FUT" | "FINAL" | "HALFTIME";
export type Leagues = "NBA" | "NHL";

export interface ChannelStream {
    baseUrl: string;
    extension: string;
    defaultChannel: string;
    title: string;
    provider: TStreamProvider;
}

export interface GameTeam {
    name: string;
    abbrev: string;
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


type StreamBuilder = (game: GameProps) => string;

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

