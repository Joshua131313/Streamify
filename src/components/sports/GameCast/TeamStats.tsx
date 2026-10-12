import type {
    SportDisplayGame
} from "../../../types/sports/sportsDisplayTypes";

interface Props {
    game: SportDisplayGame;
}

export const TeamStats = ({
    game
}: Props) => {

    switch (game.league) {

        case "MLB":

            return (
                <div className="gamecast-stats">

                    <div>
                        Away Hits:
                        {game.raw.awayTeam.hits}
                    </div>

                    <div>
                        Home Hits:
                        {game.raw.homeTeam.hits}
                    </div>

                    <div>
                        Away Errors:
                        {game.raw.awayTeam.errors}
                    </div>

                    <div>
                        Home Errors:
                        {game.raw.homeTeam.errors}
                    </div>

                </div>
            );

        case "NBA":
        case "WNBA":

            return (
                <div className="gamecast-stats">

                    <div>
                        Away Fouls:
                        {game.raw.awayTeam.fouls}
                    </div>

                    <div>
                        Home Fouls:
                        {game.raw.homeTeam.fouls}
                    </div>

                </div>
            );

        case "NHL":

            return (
                <div className="gamecast-stats">

                    <div>
                        Away Shots:
                        {game.raw.awayTeam.shots}
                    </div>

                    <div>
                        Home Shots:
                        {game.raw.homeTeam.shots}
                    </div>

                </div>
            );

        default:
            return null;
    }
};