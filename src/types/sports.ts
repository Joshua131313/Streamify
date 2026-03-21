export type IGame = {
  date: string;
  game: string;
  stream: string;
  channel: number;
  streamProvider: TStreamProvider;
  homeTeam: {
    name: string;
    logo: string;
  };
  awayTeam: {
    name: string;
    logo: string;
  };
};

export type TStreamProvider = "sharkstreams";

export type IGames = IGame[];