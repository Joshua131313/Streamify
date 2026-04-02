import { Link } from "react-router-dom";
import { Container } from "../../components/layout/Container/Container"
import "./Auth.css"
import { Button } from "../../components/ui/Button/Button";
import GoogleIcon from "./GoogleIcon";
import AppleIcon from "./AppleIcon";
interface Props {
    type: "login" | "register";
    children: React.ReactNode;
    childrenContainerClassName: string;
    title: string;
    onSubmit: () => void;
}

export const Auth = (props: Props) => {
    const { childrenContainerClassName, title, type, onSubmit } = props;

    return (
        <Container className="auth" styled>
            <div className="auth-bg">
                <img src="/images/auth-bg.jpg"/>
            </div>
            <div className={`auth-form ${childrenContainerClassName}`}>
                <div className="auth-header">
                    <h1>{title}</h1>
                    <span>Don't have an account? <Link to={"/register"}>Register</Link></span>
                </div>
                <form onSubmit={(e) => {
                    e.preventDefault();
                    onSubmit();
                }}>
                    {props.children}
                </form>
                <div className="divider">
                    <span>Or continue with</span>
                </div>
                <div className="auth-providers">
                    <Button className="secondary">
                        <GoogleIcon />
                        <span>Continue with Google</span>
                    </Button>
                    <Button className="secondary">
                        <AppleIcon />
                        <span>Continue with Apple</span>
                    </Button>
                </div>
            </div>
        </Container>
    )
}