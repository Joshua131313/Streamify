import { useSports } from "../../../context/SportsContext";
import { Container } from "./Container";

export const FilteredSportsContainer = ({ type, title, className, children }: { type: string, className?: string, title: string, children: React.ReactNode }) => {
    const { filters } = useSports();

    const hasLeagueFilter = filters.some(f => f.type === "league");

    if (hasLeagueFilter && !filters.some(f => f.value === type)) {
        return null;
    }

    return <Container className={className} title={title}>{children}</Container>;
};