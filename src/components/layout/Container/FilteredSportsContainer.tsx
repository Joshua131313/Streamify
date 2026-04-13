import { useSports } from "../../../context/SportsContext";
import type { Leagues } from "../../../types/sports/sportsTypes";
import { Container } from "./Container";

export const FilteredSportsContainer = ({ type, title, className, children }: { type?: Leagues | "TV" | "FOLLOW", className?: string, title: string, children: React.ReactNode }) => {
    const { filters } = useSports();

    const hasLeagueFilter =  type !== "FOLLOW" &&  filters.some(f => f.type === "league");

    if (hasLeagueFilter && !filters.some(f => f.value === type)) {
        return null;
    }

    return <Container className={className} title={title}>{children}</Container>;
};