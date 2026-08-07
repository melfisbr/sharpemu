# Validação estática

- arquivo completo `VulkanVideoPresenter.cs` incluído;
- helper de espera por timeline adicionado uma única vez;
- snapshot publicado somente após conclusão do fence;
- tratamento de `VK_ERROR_DEVICE_LOST` preservado;
- matemática de Fit/Cover/Integer não alterada;
- script executa build do CLI e 799 testes de Libs na máquina do usuário.

Observação: o SDK .NET não está disponível neste ambiente, portanto build e
testes são executados pelo script no repositório do usuário.
