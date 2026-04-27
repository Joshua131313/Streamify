
import { Model } from "../ui/Model/Model"
import { Customization } from "./Customization";
import "./Onboarding.css"

interface Props {
    open: boolean;
    onClose: () => void;
}

export const OnboardingModel = (props: Props) => {
    console.log("mode", props.open)
    return (
        <Model open={props.open} onClose={props.onClose}>
            <Customization onClose={props.onClose}/>
        </Model>
    )
}