import type {
    SportDisplayGame
} from "../../../types/sports/sportsDisplayTypes";

import { MLBGameCardLinescore }
from "../GameCard/mlb/components/MLBGameCardLinescore";
import { NHLLinescore } from "../GameCard/nhl/components/NHLLineScore";

interface Props {
    game: SportDisplayGame;
}

export const Scoreboard = ({
    game
}: Props) => {

    switch (game.league) {

        case "MLB":

            return (
                <MLBGameCardLinescore
                    game={game.raw}
                    card={game.card}
                />
            );

        case "NBA":
        case "WNBA":

            return (
                <div>
                    TODO:
                    NBALinescore
                </div>
            );

        case "NHL":

            return (
                <NHLLinescore card={game.card} game={game.raw}/>
            );

        default:
            return null;
    }
};