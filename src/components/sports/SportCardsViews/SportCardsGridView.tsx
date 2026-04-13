import type { SportCardsViewsProps } from ".";
import type { GameProps, Leagues } from "../../../types/sports/sportsTypes";
import { FilteredSportsContainer } from "../../layout/Container/FilteredSportsContainer";
import { AppSwiper } from "../../ui/AppSwiper/AppSwiper";
import HorizontalGameCard from "../../ui/GameCard/HorizontalGameCard";
import RegularGameCard from "../../ui/GameCard/RegularGameCard";
import { SwiperSkeletonCard } from "../../ui/MediaCard/SkeletonCards/MediaSkeletonCard";
import "./SportCardsViews.css"

export const SportCardsGridView = (props: SportCardsViewsProps) => {

    const { title, type, games, gamesLoading } = props;

    return (
        <FilteredSportsContainer className="sport-cards-grid-view" type={type} title={title}>
            {games.map((gameCard) => (
                <RegularGameCard
                    game={gameCard}
                />
            ))}
        </FilteredSportsContainer>
    )
}