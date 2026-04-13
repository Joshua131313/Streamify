import type { SportCardsViewsProps } from ".";
import type { GameProps, Leagues } from "../../../types/sports/sportsTypes";
import { FilteredSportsContainer } from "../../layout/Container/FilteredSportsContainer";
import { AppSwiper } from "../../ui/AppSwiper/AppSwiper";
import HorizontalGameCard from "../../ui/GameCard/HorizontalGameCard";
import RegularGameCard from "../../ui/GameCard/RegularGameCard";
import { SwiperSkeletonCard } from "../../ui/MediaCard/SkeletonCards/MediaSkeletonCard";
import "./SportCardsViews.css"

export const SportCardsSliderView = (props: SportCardsViewsProps) => {

    const { title, type, games, gamesLoading } = props;
    
    return (
            <FilteredSportsContainer type={type} title={title}>
                <AppSwiper
                    isLoading={gamesLoading}
                    items={games}
                    itemKey={(item) => String(item.id ?? item.title)}
                    renderItem={(game) => (
                        <RegularGameCard game={game} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredSportsContainer>
    )
}