import type {
    SportDisplayGame
} from "../../../types/sports/sportsDisplayTypes";

import { AppImg }
from "../../ui/ImgProxy/AppImg";

interface Props {
    game: SportDisplayGame;
}

export const PlayerLeader = ({
    game
}: Props) => {

    let player: any = null;

    switch (game.league) {

        case "MLB":

            player =
                game.raw.live?.batter ??
                game.raw.live?.pitcher;

            break;

        case "NBA":
        case "WNBA":

            player =
                game.raw.live?.player;

            break;

        case "NHL":

            player =
                game.raw.live?.skater ??
                game.raw.live?.goalie;

            break;
    }

    if (!player) {
        return null;
    }

    return (
        <div className="gamecast-player">

            {player.headshot && (

                <AppImg
                    src={player.headshot}
                    alt={player.name ?? ""}
                />

            )}

            <div>

                <h3>
                    {player.shortName ??
                        player.name}
                </h3>

                <p>
                    {player.summary}
                </p>

            </div>

        </div>
    );
};