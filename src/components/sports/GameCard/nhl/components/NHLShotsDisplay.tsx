import type {
    INHLGame
} from "../../../../../types/sports/nhlTypes";

interface Props {
    game: INHLGame;
}

export const NHLShotsDisplay = ({
    game
}: Props) => {

    if (game.state === "pre") {
        return null;
    }

    return (
        <div
            style={{
                marginTop: 14,
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: 6,
            }}
        >

            <span
                style={{
                    fontSize: ".72rem",
                    fontWeight: 800,
                    opacity: .7,
                    letterSpacing: 1,
                }}
            >
                SHOTS
            </span>

            <div
                style={{
                    display: "flex",
                    gap: 12,
                    alignItems: "center",
                    fontWeight: 900,
                    fontSize: "1rem",
                }}
            >

                <span>
                    {game.live?.awayShots ?? "-"}
                </span>

                <span
                    style={{
                        opacity: .4,
                    }}
                >
                    -
                </span>

                <span>
                    {game.live?.homeShots ?? "-"}
                </span>

            </div>

        </div>
    );
};