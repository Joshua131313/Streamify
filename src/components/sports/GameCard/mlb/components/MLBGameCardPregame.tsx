interface Props {
    startTime: string;
    broadcasts?: string[];
}

export const MLBGameCardPregame = ({
    startTime,
    broadcasts
}: Props) => {
    return (
        <div className="sport-game-start">

            <span className="sport-game-start-time">
                {startTime}
            </span>

            <span className="sport-game-start-venue">
                {broadcasts?.[0] ?? "MLB.TV"}
            </span>

        </div>
    );
};