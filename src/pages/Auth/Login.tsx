import { Button } from "../../components/ui/Button/Button"
import { Input } from "../../components/ui/Input/Input"
import { Auth } from "./Auth"


export const Login = () => {

    const handleLogin = () => {

    }

    return (
        <Auth onSubmit={handleLogin} title="Login" type="login" childrenContainerClassName="login">
            <Input placeholder="Email"/>
            <Input placeholder="Password"/>
            <Button>
                Login
            </Button>
        </Auth>
    )
}