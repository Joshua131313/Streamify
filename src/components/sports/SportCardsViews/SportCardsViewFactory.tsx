import type { SportCardsViewsProps } from ".";
import { useSports, type SportsCardsLayout } from "../../../context/SportsContext"
import { SportCardsGridView } from "./SportCardsGridView";
import { SportCardsListView } from "./SportCardsListView";
import { SportCardsSliderView } from "./SportCardsSliderView";
import "./SportCardsViews.css"


export const SportCardsViewFactory = (props: SportCardsViewsProps) => {
    const { layout } = useSports();

    switch(layout) {
        case "grid":
            return <SportCardsGridView   {...props}  />
        case "list":
            return <SportCardsListView   {...props}  />
        case "slider":
            return <SportCardsSliderView {...props}  />
    }

}