import { Container } from "../../layout/Container/Container"
import "./PageHeader.css"

interface Props {
    controls: React.ReactNode;
    title: string;
    subTitle: string;
}

export const PageHeader = (props: Props) => {
    const { controls, title, subTitle } = props;
    return (
        <Container className="page-header-container">
            <div className="header-title">
                <h1>{title}</h1>
                <span>{subTitle}</span>
            </div>
            <Container className="header-controls" styled>
                {controls}
            </Container>
        </Container>
    )
}