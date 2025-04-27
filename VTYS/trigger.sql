IF OBJECT_ID('dbo.trg_TarifelerKontrol', 'TR') IS NOT NULL
BEGIN
    DROP TRIGGER trg_TarifelerKontrol;
END;
GO

-- Bu trigger, tarifelerde yap�lan ekleme, g�ncelleme veya silme i�lemlerini denetler. 3 ay kural�n� ve �denmemi� faturalar� kontrol ederek veri b�t�nl���n� sa�lar.
CREATE TRIGGER trg_TarifelerKontrol
ON TARIFELER
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRANSACTION;

    BEGIN TRY
        DECLARE @SozlesmeNumarasi INT, @IlkTarih DATE;

        -- 3 Ay Kural� i�in veriler hem DELETED hem de INSERTED tablosundan al�nabilir
		-- DELETE i�lemi i�in DELETED tablosundan veri al�m�
		IF EXISTS (SELECT 1 FROM DELETED)
		BEGIN
			SELECT @SozlesmeNumarasi = SOZLESME_NUMARASI, @IlkTarih = ILK_TARIH
			FROM DELETED;
		END
		-- UPDATE i�lemi i�in DELETED ve INSERTED tablosundan veri al�m�
		ELSE IF EXISTS (SELECT 1 FROM INSERTED)
		BEGIN
			SELECT @SozlesmeNumarasi = SOZLESME_NUMARASI, @IlkTarih = ILK_TARIH
			FROM INSERTED;
		END

		-- 3 ay kural�n� kontrol et
		IF EXISTS (
			SELECT 1
			FROM TARIFELER
			WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi
			  AND DATEDIFF(MONTH, @IlkTarih, GETDATE()) < 3
		)
		BEGIN
			RAISERROR ('Mevcut tarifede 3 aydan daha k�sa s�rede bulundu�unuz i�in tarife de�i�ikli�i yapamazs�n�z.', 16, 1);
			ROLLBACK TRANSACTION;
			RETURN;
		END


        -- �denmemi� faturalar kontrol�
        IF EXISTS (
            SELECT 1
            FROM FATURA
            WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi
              AND ODENME_TARIHI IS NULL
              AND SON_ODEME_BITIS_TARIHI < GETDATE()
        )
        BEGIN
            RAISERROR ('�denmemi� faturalar�n�z bulundu�u i�in yeni tarife atamas� yapamazs�n�z.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Tarife de�i�ikli�i sonras� ilgili tarifeyi g�ncelleme
        IF EXISTS (SELECT 1 FROM INSERTED WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi)
        BEGIN
            UPDATE TARIFELER
            SET ISIM = (SELECT ISIM FROM INSERTED WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi)
            WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi;
        END

        COMMIT TRANSACTION;
		-- Ba�ar�l� i�lem mesaj�
		PRINT 'Tarife de�i�ikli�i ba�ar�yla tamamland�.';

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR (@ErrorMessage, 16, 1);
    END CATCH
END;


-- TRIGGER TESTLERI
-------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- 1. Test: 3 ay kural� - Tarife De�i�ikli�i
INSERT INTO TARIFELER (ISIM, ILK_TARIH, SOZLESME_NUMARASI, BASVURU_YASI) 
VALUES ('Eski Tarife', GETDATE(), 1, 30);
	


UPDATE TARIFELER 
SET ISIM = 'Yeni Tarife', ILK_TARIH = DATEADD(MONTH, -2, GETDATE())
WHERE SOZLESME_NUMARASI = 1;

-- Bu i�lem s�ras�nda 3 ay kural� sebebiyle hata verilmelidir ve rollback at�lmal�d�r.

----------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- 2. Test: �denmemi� Fatura Testi
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

-- Bu i�lemde �denmemi� faturalar bulundu�u i�in rollback at�lmal�d�r.

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- 3. Test: Ba�ar�l� Tarife De�i�ikli�i
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


-- Test sonu�lar�n� kontrol etmek i�in SELECT sorgular�

SELECT * FROM TARIFELER WHERE SOZLESME_NUMARASI = 3;


SELECT * FROM FATURA WHERE SOZLESME_NUMARASI = 3;

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- 4.Test: 3 aydan �nce silme testi
INSERT INTO TARIFELER (ISIM, ILK_TARIH, SOZLESME_NUMARASI, BASVURU_YASI) 
VALUES ('Silinemez Tarife', GETDATE(), 3, 25);


DELETE FROM TARIFELER 
WHERE SOZLESME_NUMARASI = 3;

-- Beklenen sonu�: "Mevcut tarifede 3 aydan daha k�sa s�rede bulundu�unuz i�in tarife de�i�ikli�i yapamazs�n�z."