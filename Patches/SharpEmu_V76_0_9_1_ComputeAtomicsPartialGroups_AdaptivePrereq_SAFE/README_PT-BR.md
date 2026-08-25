# V76.0.9.1 SAFE

Use sobre o source que já concluiu V76.0.8 BUILD + VERIFY. Esta revisão corrige somente o precheck/adaptive prerequisite da V76.0.9.

O pacote não confia em hashes integrais dos arquivos grandes. Ele valida o helper V76.0.8 por SHA-256 e, para os quatro pontos V76.0.8 no translator, aceita estado já aplicado ou uma âncora antiga única que possa ser reparada in-place antes da V76.0.9.

Se qualquer âncora estiver divergente de forma não reconhecida, o apply é recusado antes da primeira escrita. RUN_4 só deve ser executado depois de BUILD PASSED.
