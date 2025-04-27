IF OBJECT_ID('dbo.trg_TarifelerKontrol', 'TR') IS NOT NULL
BEGIN
    DROP TRIGGER trg_TarifelerKontrol;
END;
GO

-- Bu trigger, tarifelerde yapýlan ekleme, güncelleme veya silme iþlemlerini denetler. 3 ay kuralýný ve ödenmemiþ faturalarý kontrol ederek veri bütünlüðünü saðlar.
CREATE TRIGGER trg_TarifelerKontrol
ON TARIFELER
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRANSACTION;

    BEGIN TRY
        DECLARE @SozlesmeNumarasi INT, @IlkTarih DATE;

        -- 3 Ay Kuralý için veriler hem DELETED hem de INSERTED tablosundan alýnabilir
		-- DELETE iþlemi için DELETED tablosundan veri alýmý
		IF EXISTS (SELECT 1 FROM DELETED)
		BEGIN
			SELECT @SozlesmeNumarasi = SOZLESME_NUMARASI, @IlkTarih = ILK_TARIH
			FROM DELETED;
		END
		-- UPDATE iþlemi için DELETED ve INSERTED tablosundan veri alýmý
		ELSE IF EXISTS (SELECT 1 FROM INSERTED)
		BEGIN
			SELECT @SozlesmeNumarasi = SOZLESME_NUMARASI, @IlkTarih = ILK_TARIH
			FROM INSERTED;
		END

		-- 3 ay kuralýný kontrol et
		IF EXISTS (
			SELECT 1
			FROM TARIFELER
			WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi
			  AND DATEDIFF(MONTH, @IlkTarih, GETDATE()) < 3
		)
		BEGIN
			RAISERROR ('Mevcut tarifede 3 aydan daha kýsa sürede bulunduðunuz için tarife deðiþikliði yapamazsýnýz.', 16, 1);
			ROLLBACK TRANSACTION;
			RETURN;
		END


        -- Ödenmemiþ faturalar kontrolü
        IF EXISTS (
            SELECT 1
            FROM FATURA
            WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi
              AND ODENME_TARIHI IS NULL
              AND SON_ODEME_BITIS_TARIHI < GETDATE()
        )
        BEGIN
            RAISERROR ('Ödenmemiþ faturalarýnýz bulunduðu için yeni tarife atamasý yapamazsýnýz.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Tarife deðiþikliði sonrasý ilgili tarifeyi güncelleme
        IF EXISTS (SELECT 1 FROM INSERTED WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi)
        BEGIN
            UPDATE TARIFELER
            SET ISIM = (SELECT ISIM FROM INSERTED WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi)
            WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi;
        END

        COMMIT TRANSACTION;
		-- Baþarýlý iþlem mesajý
		PRINT 'Tarife deðiþikliði baþarýyla tamamlandý.';

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR (@ErrorMessage, 16, 1);
    END CATCH
END;


-- TRIGGER TESTLERI
-------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- 1. Test: 3 ay kuralý - Tarife Deðiþikliði
INSERT INTO TARIFELER (ISIM, ILK_TARIH, SOZLESME_NUMARASI, BASVURU_YASI) 
VALUES ('Eski Tarife', GETDATE(), 1, 30);
	


UPDATE TARIFELER 
SET ISIM = 'Yeni Tarife', ILK_TARIH = DATEADD(MONTH, -2, GETDATE())
WHERE SOZLESME_NUMARASI = 1;

-- Bu iþlem sýrasýnda 3 ay kuralý sebebiyle hata verilmelidir ve rollback atýlmalýdýr.

----------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- 2. Test: Ödenmemiþ Fatura Testi
DELETE FROM FATURA WHERE SOZLESME_NUMARASI = 3;
DELETE FROM TARIFELER WHERE SOZLESME_NUMARASI = 3;


INSERT INTO TARIFELER (ISIM, ILK_TARIH, SOZLESME_NUMARASI, BASVURU_YASI) 
VALUES ('Eski Tarife', DATEADD(MONTH, -6, GETDATE()), 3, 30);


INSERT INTO FATURA (SOZLESME_NUMARASI, FATURA_TUTARI, FATURA_KESIM_TARIHI, SON_ODEME_BITIS_TARIHI, ODENME_TARIHI) 
VALUES (3, 150.00, DATEADD(MONTH, -2, GETDATE()), DATEADD(MONTH, -1, GETDATE()), NULL);


UPDATE TARIFELER 
SET ISIM = 'Yeni Tarife'
WHERE SOZLESME_NUMARASI = 3;


SELECT * FROM TARIFELER WHERE SOZLESME_NUMARASI = 3;
SELECT * FROM FATURA WHERE SOZLESME_NUMARASI = 3;

-- Bu iþlemde ödenmemiþ faturalar bulunduðu için rollback atýlmalýdýr.

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- 3. Test: Baþarýlý Tarife Deðiþikliði
DELETE FROM FATURA WHERE SOZLESME_NUMARASI = 3;
DELETE FROM TARIFELER WHERE SOZLESME_NUMARASI = 3;


INSERT INTO TARIFELER (ISIM, ILK_TARIH, SOZLESME_NUMARASI, BASVURU_YASI) 
VALUES ('Eski Tarife', DATEADD(MONTH, -4, GETDATE()), 3, 25);


INSERT INTO FATURA (FATURA_TUTARI, FATURA_KESIM_TARIHI, FATURA_BASLANGIC_TARIHI, FATURA_BITIS_TARIHI, SON_ODEME_BITIS_TARIHI, ODENME_TARIHI, SOZLESME_NUMARASI)
VALUES 
(150.00, DATEADD(MONTH, -3, GETDATE()), DATEADD(MONTH, -4, GETDATE()), DATEADD(MONTH, -3, GETDATE()), DATEADD(MONTH, -2, GETDATE()), GETDATE(), 3);


UPDATE TARIFELER 
SET ISIM = 'Yeni Tarife'
WHERE SOZLESME_NUMARASI = 3;


-- Test sonuçlarýný kontrol etmek için SELECT sorgularý

SELECT * FROM TARIFELER WHERE SOZLESME_NUMARASI = 3;


SELECT * FROM FATURA WHERE SOZLESME_NUMARASI = 3;

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- 4.Test: 3 aydan önce silme testi
INSERT INTO TARIFELER (ISIM, ILK_TARIH, SOZLESME_NUMARASI, BASVURU_YASI) 
VALUES ('Silinemez Tarife', GETDATE(), 3, 25);


DELETE FROM TARIFELER 
WHERE SOZLESME_NUMARASI = 3;

-- Beklenen sonuç: "Mevcut tarifede 3 aydan daha kýsa sürede bulunduðunuz için tarife deðiþikliði yapamazsýnýz."