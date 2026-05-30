import type {
    SportDisplayGame
} from "../../../types/sports/sportsDisplayTypes";

interface Props {
    game: SportDisplayGame;
}

export const PlayByPlay = ({
    game
}: Props) => {

    let playText: string | null = null;

    switch (game.league) {

        case "MLB":

            playText =
                game.raw.live?.lastPlay?.text ??
                null;

            break;

        case "NBA":
        case "WNBA":

            playText =
                game.raw.live?.lastPlay?.text ??
                null;

            break;

        case "NHL":

            playText =
                game.raw.live?.lastPlay?.text ??
                null;

            break;
    }

    if (!playText) {
        return null;
    }

    return (
        <div className="gamecast-play">

            <h3>
                Last Play
            </h3>

            <p>
                {playText}
            </p>

        </div>
    );
};