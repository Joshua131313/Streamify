import React from "react";

interface Props {
    periodsPlayed: number;
    children: React.ReactNode;
}

export const PeriodGroup = ({
    periodsPlayed,
    children
}: Props) => {
    return (
        <div
            className="innings-group"
            style={{
                gridTemplateColumns:
                    `repeat(${periodsPlayed}, minmax(14px, 1fr))`
            }}
        >
            {children}
        </div>
    );
};