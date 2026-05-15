interface Props {
    bases?: {
        first?: boolean;
        second?: boolean;
        third?: boolean;
    };
    outs: number;
}

export const MLBDiamond = ({
    bases,
    outs
}: Props) => {
    return (
        <>
            <div
                className="mlb-diamond"
                aria-label="base runners"
            >
                <span
                    className={`base second ${
                        bases?.second ? "filled" : ""
                    }`}
                />

                <span
                    className={`base third ${
                        bases?.third ? "filled" : ""
                    }`}
                />

                <span
                    className={`base first ${
                        bases?.first ? "filled" : ""
                    }`}
                />
            </div>

            <div
                className="mlb-outs"
                aria-label={`${outs} outs`}
            >
                <span
                    className={`out ${
                        outs >= 1 ? "filled" : ""
                    }`}
                />

                <span
                    className={`out ${
                        outs >= 2 ? "filled" : ""
                    }`}
                />
            </div>
        </>
    );
};