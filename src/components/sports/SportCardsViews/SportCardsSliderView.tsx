import type { SportCardsViewsProps } from ".";
import { FilteredSportsContainer } from "../../layout/Container/FilteredSportsContainer";
import { AppSwiper } from "../../ui/AppSwiper/AppSwiper";
import { GameCardSkeleton } from "../GameCard/GameCardSkeleton/GameCardSkeleton";
import { SportGameCardRenderer } from "../GameCard/SportGameCardRenderer";
import "./SportCardsViews.css";

export const SportCardsSliderView = (
    props: SportCardsViewsProps
) => {
    const {
        title,
        type,
        games,
        gamesLoading,
    } = props;

    return (
        <FilteredSportsContainer
            type={type}
            title={title}
        >
            <AppSwiper
                isLoading={gamesLoading}
                items={games}
                itemKey={(item) =>
                    `${item.league}-${item.id}`
                }
                renderItem={(game) => (
                    <SportGameCardRenderer
                        game={game}
                    />
                )}
                skeleton={
                    <GameCardSkeleton
                        className="game-card-skeleton"
                    />
                }
            />
        </FilteredSportsContainer>
    );
};