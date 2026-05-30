import type {
    INHLGame
} from "../../../../../types/sports/nhlTypes";

interface Props {
    game: INHLGame;
}

export const NHLLastPlay = ({
    game
}: Props) => {

    const lastPlay =
        game.live?.lastPlay;

    const player =
        game.live?.skater ||
        game.live?.goalie;

    if (!lastPlay) {
        return null;
    }

    return (
        <div
            className="sport-live-info"
            style={{
                marginBottom: 4,
            }}
        >

            <div
                className="sport-live-line batter"
            >

                <span
                    className="sport-line-indicator"
                />

                {player?.headshot && (
                    <img
                        src={player.headshot}
                        alt={player.name ?? ""}
                        style={{
                            width: 38,
                            height: 38,
                            borderRadius: 999,
                            objectFit: "cover",
                            border:
                                "1px solid var(--border)",
                        }}
                    />
                )}

                <div className="sport-player-copy">

                    <span className="sport-player-role">
                        Last Play
                    </span>

                    <span className="sport-player-name">
                        {lastPlay.text}
                    </span>

                </div>

            </div>

        </div>
    );
};