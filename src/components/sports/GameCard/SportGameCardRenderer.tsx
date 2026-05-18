import type { SportDisplayGame } from "../../../types/sports/sportsDisplayTypes";

import MLBGameCard from "../GameCard/mlb/MLBGameCard";
import NBAGameCard from "./nba/NBAGameCard";
import NHLGameCard from "./nhl/NHLGameCard";

type Props = {
    game: SportDisplayGame;
};

export const SportGameCardRenderer = ({
    game,
}: Props) => {
    switch (game.league) {
        case "MLB":
            return (
                <MLBGameCard
                    card={game.card}
                    game={game.raw}
                />
            );
        case "WNBA":
        case "NBA": 
            return (
                <NBAGameCard
                    game={game.raw}
                    card={game.card}
                />
            );

        case "NHL":
            return (
                <NHLGameCard
                    game={game.raw}
                    card={game.card}
                />
            );

        default:
            return null;
    }
};